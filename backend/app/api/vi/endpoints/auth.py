#!/usr/bin/env python3
"""
Authentication endpoints for OCI IDCS SSO Platform
"""

import logging
from typing import Any, Dict, Optional
from urllib.parse import urlencode, quote

from fastapi import APIRouter, Depends, HTTPException, Request, Response, Form
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings
from app.schemas.auth import (
    LoginRequest, LoginResponse, TokenResponse, UserInfo,
    SAMLRequest, SAMLResponse, OAuthCallback
)
from app.services.auth.idcs_service import IDCSService
from app.services.auth.ldap_service import LDAPService
from app.services.auth.saml_service import SAMLService
from app.services.auth.jwt_service import JWTService
from app.services.auth.session_service import SessionService
from app.core.exceptions import AuthenticationError, AuthorizationError
from app.core.dependencies import get_current_user, get_current_active_user

logger = logging.getLogger(__name__)
router = APIRouter()
security = HTTPBearer(auto_error=False)
limiter = Limiter(key_func=get_remote_address)

# Services
idcs_service = IDCSService()
ldap_service = LDAPService()
saml_service = SAMLService()
jwt_service = JWTService()
session_service = SessionService()


# =================================================================
# OAuth 2.0 / OpenID Connect Endpoints
# =================================================================

@router.get("/oauth/authorize")
@limiter.limit("10/minute")
async def oauth_authorize(request: Request, redirect_uri: Optional[str] = None):
    """
    OAuth 2.0 authorization endpoint - redirects to IDCS
    """
    try:
        # Generate state parameter for CSRF protection
        state = await session_service.generate_state()
        
        # Store state in session
        await session_service.store_oauth_state(request, state, redirect_uri)
        
        # Build authorization URL
        auth_params = {
            'response_type': settings.IDCS_RESPONSE_TYPE,
            'client_id': settings.IDCS_CLIENT_ID,
            'redirect_uri': settings.IDCS_REDIRECT_URI,
            'scope': settings.IDCS_SCOPE,
            'state': state
        }
        
        authorization_url = f"{settings.idcs_authorization_url}?{urlencode(auth_params)}"
        
        logger.info(f"Redirecting to IDCS OAuth authorization: {authorization_url}")
        return RedirectResponse(url=authorization_url)
        
    except Exception as e:
        logger.error(f"OAuth authorization error: {e}")
        raise HTTPException(status_code=500, detail="OAuth authorization failed")


@router.get("/oauth/callback")
@limiter.limit("20/minute")
async def oauth_callback(
    request: Request,
    code: Optional[str] = None,
    state: Optional[str] = None,
    error: Optional[str] = None,
    error_description: Optional[str] = None
):
    """
    OAuth 2.0 callback endpoint - handles IDCS response
    """
    try:
        # Check for error response
        if error:
            logger.error(f"OAuth error: {error} - {error_description}")
            raise HTTPException(
                status_code=400,
                detail=f"OAuth authentication failed: {error_description or error}"
            )
        
        if not code or not state:
            raise HTTPException(status_code=400, detail="Missing code or state parameter")
        
        # Verify state parameter
        stored_state, redirect_uri = await session_service.verify_oauth_state(request, state)
        if not stored_state:
            raise HTTPException(status_code=400, detail="Invalid state parameter")
        
        # Exchange authorization code for tokens
        token_response = await idcs_service.exchange_code_for_tokens(code)
        
        # Get user information
        user_info = await idcs_service.get_user_info(token_response.access_token)
        
        # Create local JWT token
        jwt_token = await jwt_service.create_access_token(
            user_id=user_info.sub,
            email=user_info.email,
            extra_data={
                "source": "idcs",
                "idcs_user_id": user_info.sub,
                "groups": user_info.groups,
                "first_name": user_info.given_name,
                "last_name": user_info.family_name
            }
        )
        
        # Store session
        await session_service.create_session(
            request,
            user_id=user_info.sub,
            tokens={
                "access_token": token_response.access_token,
                "refresh_token": token_response.refresh_token,
                "id_token": token_response.id_token,
                "jwt_token": jwt_token
            }
        )
        
        logger.info(f"OAuth login successful for user: {user_info.email}")
        
        # Redirect to frontend with token
        frontend_url = redirect_uri or f"{settings.FRONTEND_URL}/dashboard"
        response = RedirectResponse(url=f"{frontend_url}?token={jwt_token}")
        
        # Set secure cookie
        response.set_cookie(
            key=settings.SESSION_COOKIE_NAME,
            value=jwt_token,
            max_age=settings.SESSION_EXPIRE_SECONDS,
            httponly=settings.SESSION_COOKIE_HTTPONLY,
            secure=settings.SESSION_COOKIE_SECURE,
            samesite=settings.SESSION_COOKIE_SAMESITE
        )
        
        return response
        
    except Exception as e:
        logger.error(f"OAuth callback error: {e}")
        raise HTTPException(status_code=500, detail="OAuth callback processing failed")


@router.post("/oauth/refresh")
@limiter.limit("30/minute")
async def oauth_refresh(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Refresh OAuth tokens
    """
    try:
        # Get current session
        session_data = await session_service.get_session(request)
        if not session_data or "refresh_token" not in session_data.get("tokens", {}):
            raise HTTPException(status_code=401, detail="No refresh token available")
        
        refresh_token = session_data["tokens"]["refresh_token"]
        
        # Refresh tokens
        token_response = await idcs_service.refresh_tokens(refresh_token)
        
        # Update session with new tokens
        session_data["tokens"].update({
            "access_token": token_response.access_token,
            "id_token": token_response.id_token
        })
        
        if token_response.refresh_token:
            session_data["tokens"]["refresh_token"] = token_response.refresh_token
        
        await session_service.update_session(request, session_data)
        
        return TokenResponse(
            access_token=token_response.access_token,
            token_type="bearer",
            expires_in=token_response.expires_in
        )
        
    except Exception as e:
        logger.error(f"Token refresh error: {e}")
        raise HTTPException(status_code=500, detail="Token refresh failed")


# =================================================================
# SAML 2.0 Endpoints
# =================================================================

@router.get("/saml/login")
@limiter.limit("10/minute")
async def saml_login(request: Request, redirect_uri: Optional[str] = None):
    """
    SAML 2.0 login endpoint - redirects to IDCS SAML IdP
    """
    try:
        # Generate SAML request
        saml_request, request_id = await saml_service.create_authn_request()
        
        # Store request ID for validation
        await session_service.store_saml_request_id(request, request_id, redirect_uri)
        
        # Build SSO URL
        sso_params = {
            'SAMLRequest': saml_request,
            'RelayState': redirect_uri or settings.FRONTEND_URL
        }
        
        sso_url = f"{settings.SAML_IDP_SSO_URL}?{urlencode(sso_params)}"
        
        logger.info(f"Redirecting to IDCS SAML SSO: {sso_url}")
        return RedirectResponse(url=sso_url)
        
    except Exception as e:
        logger.error(f"SAML login error: {e}")
        raise HTTPException(status_code=500, detail="SAML login failed")


@router.post("/saml/acs")
@limiter.limit("20/minute")
async def saml_acs(
    request: Request,
    SAMLResponse: str = Form(...),
    RelayState: Optional[str] = Form(None)
):
    """
    SAML 2.0 Assertion Consumer Service (ACS) endpoint
    """
    try:
        # Validate SAML response
        user_info = await saml_service.process_saml_response(SAMLResponse)
        
        # Verify request ID if stored
        if hasattr(user_info, 'in_response_to'):
            stored_request_id = await session_service.get_saml_request_id(request)
            if stored_request_id and stored_request_id != user_info.in_response_to:
                raise HTTPException(status_code=400, detail="Invalid SAML response")
        
        # Create JWT token
        jwt_token = await jwt_service.create_access_token(
            user_id=user_info.name_id,
            email=user_info.email,
            extra_data={
                "source": "saml",
                "saml_name_id": user_info.name_id,
                "groups": user_info.groups,
                "first_name": user_info.first_name,
                "last_name": user_info.last_name,
                "attributes": user_info.attributes
            }
        )
        
        # Store session
        await session_service.create_session(
            request,
            user_id=user_info.name_id,
            tokens={"jwt_token": jwt_token}
        )
        
        logger.info(f"SAML login successful for user: {user_info.email}")
        
        # Redirect to frontend
        redirect_url = RelayState or f"{settings.FRONTEND_URL}/dashboard"
        response = RedirectResponse(url=f"{redirect_url}?token={jwt_token}")
        
        # Set secure cookie
        response.set_cookie(
            key=settings.SESSION_COOKIE_NAME,
            value=jwt_token,
            max_age=settings.SESSION_EXPIRE_SECONDS,
            httponly=settings.SESSION_COOKIE_HTTPONLY,
            secure=settings.SESSION_COOKIE_SECURE,
            samesite=settings.SESSION_COOKIE_SAMESITE
        )
        
        return response
        
    except Exception as e:
        logger.error(f"SAML ACS error: {e}")
        raise HTTPException(status_code=500, detail="SAML assertion processing failed")


@router.get("/saml/sls")
@router.post("/saml/sls")
@limiter.limit("10/minute")
async def saml_sls(
    request: Request,
    SAMLRequest: Optional[str] = None,
    SAMLResponse: Optional[str] = None,
    RelayState: Optional[str] = None
):
    """
    SAML 2.0 Single Logout Service (SLS) endpoint
    """
    try:
        if SAMLRequest:
            # Handle logout request from IdP
            logout_request = await saml_service.process_logout_request(SAMLRequest)
            
            # Destroy local session
            await session_service.destroy_session(request)
            
            # Create logout response
            logout_response = await saml_service.create_logout_response(logout_request.id)
            
            # Redirect to IdP with response
            slo_params = {
                'SAMLResponse': logout_response,
                'RelayState': RelayState or settings.FRONTEND_URL
            }
            
            slo_url = f"{settings.SAML_IDP_SLO_URL}?{urlencode(slo_params)}"
            return RedirectResponse(url=slo_url)
            
        elif SAMLResponse:
            # Handle logout response from IdP
            await saml_service.process_logout_response(SAMLResponse)
            
            # Destroy local session
            await session_service.destroy_session(request)
            
            # Redirect to login page
            return RedirectResponse(url=RelayState or f"{settings.FRONTEND_URL}/login")
        
        else:
            # Initiate logout
            await session_service.destroy_session(request)
            return RedirectResponse(url=f"{settings.FRONTEND_URL}/login")
            
    except Exception as e:
        logger.error(f"SAML SLS error: {e}")
        raise HTTPException(status_code=500, detail="SAML logout failed")


@router.get("/saml/metadata")
async def saml_metadata():
    """
    SAML 2.0 Service Provider metadata endpoint
    """
    try:
        metadata_xml = await saml_service.get_sp_metadata()
        return Response(content=metadata_xml, media_type="application/xml")
        
    except Exception as e:
        logger.error(f"SAML metadata error: {e}")
        raise HTTPException(status_code=500, detail="SAML metadata generation failed")


# =================================================================
# LDAP Direct Authentication
# =================================================================

@router.post("/ldap/login")
@limiter.limit("5/minute")
async def ldap_login(request: Request, login_data: LoginRequest):
    """
    Direct LDAP authentication
    """
    try:
        if not settings.FEATURE_DIRECT_LDAP_LOGIN:
            raise HTTPException(status_code=403, detail="LDAP login is disabled")
        
        # Authenticate with LDAP
        user_info = await ldap_service.authenticate(login_data.username, login_data.password)
        
        # Create JWT token
        jwt_token = await jwt_service.create_access_token(
            user_id=user_info.uid,
            email=user_info.email,
            extra_data={
                "source": "ldap",
                "ldap_dn": user_info.dn,
                "groups": user_info.groups,
                "first_name": user_info.first_name,
                "last_name": user_info.last_name,
                "attributes": user_info.attributes
            }
        )
        
        # Store session
        await session_service.create_session(
            request,
            user_id=user_info.uid,
            tokens={"jwt_token": jwt_token}
        )
        
        logger.info(f"LDAP login successful for user: {user_info.email}")
        
        return LoginResponse(
            access_token=jwt_token,
            token_type="bearer",
            expires_in=settings.JWT_EXPIRE_MINUTES * 60,
            user_info=UserInfo(
                user_id=user_info.uid,
                email=user_info.email,
                first_name=user_info.first_name,
                last_name=user_info.last_name,
                groups=user_info.groups,
                source="ldap"
            )
        )
        
    except AuthenticationError as e:
        logger.warning(f"LDAP authentication failed: {e}")
        raise HTTPException(status_code=401, detail=str(e))
    except Exception as e:
        logger.error(f"LDAP login error: {e}")
        raise HTTPException(status_code=500, detail="LDAP login failed")


# =================================================================
# Common Authentication Endpoints
# =================================================================

@router.post("/logout")
@limiter.limit("20/minute")
async def logout(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Logout endpoint - supports both local and SSO logout
    """
    try:
        # Get session data
        session_data = await session_service.get_session(request)
        
        # Determine logout type
        user_source = current_user.get("source", "local")
        
        if user_source == "saml" and settings.FEATURE_SAML_LOGIN:
            # SAML Single Logout
            logout_request = await saml_service.create_logout_request(current_user.get("saml_name_id"))
            
            # Destroy local session
            await session_service.destroy_session(request)
            
            # Redirect to IdP for global logout
            slo_params = {
                'SAMLRequest': logout_request,
                'RelayState': f"{settings.FRONTEND_URL}/login"
            }
            
            slo_url = f"{settings.SAML_IDP_SLO_URL}?{urlencode(slo_params)}"
            return {"message": "Logout initiated", "slo_url": slo_url}
            
        elif user_source == "idcs" and settings.FEATURE_OAUTH_LOGIN:
            # OAuth logout
            await session_service.destroy_session(request)
            
            # Build IDCS logout URL
            logout_params = {
                'post_logout_redirect_uri': settings.IDCS_POST_LOGOUT_REDIRECT_URI
            }
            
            logout_url = f"{settings.IDCS_TENANT_URL}/oauth2/v1/logout?{urlencode(logout_params)}"
            return {"message": "Logout successful", "logout_url": logout_url}
        
        else:
            # Local logout
            await session_service.destroy_session(request)
            return {"message": "Logout successful"}
            
    except Exception as e:
        logger.error(f"Logout error: {e}")
        raise HTTPException(status_code=500, detail="Logout failed")


@router.get("/verify")
@limiter.limit("100/minute")
async def verify_token(
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """
    Verify JWT token and return user information
    """
    return {
        "valid": True,
        "user_info": UserInfo(
            user_id=current_user.get("user_id"),
            email=current_user.get("email"),
            first_name=current_user.get("first_name"),
            last_name=current_user.get("last_name"),
            groups=current_user.get("groups", []),
            source=current_user.get("source", "unknown"),
            attributes=current_user.get("attributes", {})
        )
    }


@router.get("/session")
@limiter.limit("50/minute")
async def get_session_info(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user)
):
    """
    Get current session information
    """
    try:
        session_data = await session_service.get_session(request)
        
        return {
            "user_id": current_user.get("user_id"),
            "email": current_user.get("email"),
            "source": current_user.get("source"),
            "groups": current_user.get("groups", []),
            "session_created": session_data.get("created_at") if session_data else None,
            "session_expires": session_data.get("expires_at") if session_data else None,
            "last_activity": session_data.get("last_activity") if session_data else None
        }
        
    except Exception as e:
        logger.error(f"Session info error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get session information")


# =================================================================
# SSO Integration Endpoints
# =================================================================

@router.post("/sso/token")
@limiter.limit("50/minute")
async def generate_sso_token(
    request: Request,
    app_id: str,
    target_url: Optional[str] = None,
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """
    Generate SSO token for external application access
    """
    try:
        # Validate application access
        external_apps = settings.external_apps_config
        app_config = next((app for app in external_apps if app["id"] == app_id), None)
        
        if not app_config:
            raise HTTPException(status_code=404, detail="Application not found")
        
        # Check user permissions
        user_groups = current_user.get("groups", [])
        required_groups = app_config.get("access_groups", [])
        
        if required_groups and not any(group in user_groups for group in required_groups):
            raise HTTPException(status_code=403, detail="Access denied")
        
        # Generate SSO token
        sso_token = await jwt_service.create_sso_token(
            user_id=current_user.get("user_id"),
            app_id=app_id,
            target_url=target_url or app_config["url"],
            user_data=current_user
        )
        
        # Build iframe URL with SSO token
        iframe_url = f"{app_config['url']}?sso_token={sso_token}"
        if target_url:
            iframe_url += f"&redirect_uri={quote(target_url)}"
        
        return {
            "sso_token": sso_token,
            "iframe_url": iframe_url,
            "app_config": app_config
        }
        
    except Exception as e:
        logger.error(f"SSO token generation error: {e}")
        raise HTTPException(status_code=500, detail="SSO token generation failed")


@router.get("/sso/apps")
@limiter.limit("30/minute")
async def get_sso_applications(
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """
    Get list of SSO applications accessible to current user
    """
    try:
        external_apps = settings.external_apps_config
        user_groups = current_user.get("groups", [])
        
        accessible_apps = []
        
        for app in external_apps:
            required_groups = app.get("access_groups", [])
            
            # Check if user has access
            if not required_groups or any(group in user_groups for group in required_groups):
                accessible_apps.append({
                    "id": app["id"],
                    "name": app["name"],
                    "description": app["description"],
                    "icon": app.get("icon"),
                    "sso_enabled": app.get("sso_enabled", False),
                    "sso_type": app.get("sso_type", "oauth"),
                    "iframe_settings": app.get("iframe_settings", {})
                })
        
        return accessible_apps
        
    except Exception as e:
        logger.error(f"Get SSO apps error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get SSO applications")


@router.post("/sso/validate")
@limiter.limit("100/minute")
async def validate_sso_token(
    sso_token: str,
    app_id: str
):
    """
    Validate SSO token for external applications
    """
    try:
        # Validate and decode SSO token
        token_data = await jwt_service.validate_sso_token(sso_token, app_id)
        
        return {
            "valid": True,
            "user_context": {
                "user_id": token_data.get("user_id"),
                "email": token_data.get("email"),
                "first_name": token_data.get("first_name"),
                "last_name": token_data.get("last_name"),
                "groups": token_data.get("groups", []),
                "source": token_data.get("source"),
                "app_id": token_data.get("app_id"),
                "target_url": token_data.get("target_url")
            }
        }
        
    except Exception as e:
        logger.error(f"SSO token validation error: {e}")
        return {"valid": False, "error": str(e)}


# =================================================================
# Admin Endpoints
# =================================================================

@router.get("/admin/sessions")
@limiter.limit("10/minute")
async def get_active_sessions(
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """
    Get active sessions (admin only)
    """
    try:
        # Check admin permissions
        user_groups = current_user.get("groups", [])
        if "admins" not in user_groups:
            raise HTTPException(status_code=403, detail="Admin access required")
        
        sessions = await session_service.get_all_active_sessions()
        return sessions
        
    except Exception as e:
        logger.error(f"Get active sessions error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get active sessions")


@router.delete("/admin/sessions/{session_id}")
@limiter.limit("10/minute")
async def revoke_session(
    session_id: str,
    current_user: Dict[str, Any] = Depends(get_current_active_user)
):
    """
    Revoke user session (admin only)
    """
    try:
        # Check admin permissions
        user_groups = current_user.get("groups", [])
        if "admins" not in user_groups:
            raise HTTPException(status_code=403, detail="Admin access required")
        
        await session_service.revoke_session(session_id)
        return {"message": "Session revoked successfully"}
        
    except Exception as e:
        logger.error(f"Revoke session error: {e}")
        raise HTTPException(status_code=500, detail="Failed to revoke session")


# =================================================================
# Health Check Endpoints
# =================================================================

@router.get("/health")
async def auth_health_check():
    """
    Authentication service health check
    """
    try:
        health_status = {
            "status": "healthy",
            "services": {}
        }
        
        # Check IDCS connectivity
        if settings.FEATURE_OAUTH_LOGIN or settings.FEATURE_SAML_LOGIN:
            try:
                await idcs_service.health_check()
                health_status["services"]["idcs"] = "healthy"
            except Exception as e:
                health_status["services"]["idcs"] = f"unhealthy: {str(e)}"
                health_status["status"] = "degraded"
        
        # Check LDAP connectivity
        if settings.FEATURE_DIRECT_LDAP_LOGIN:
            try:
                await ldap_service.health_check()
                health_status["services"]["ldap"] = "healthy"
            except Exception as e:
                health_status["services"]["ldap"] = f"unhealthy: {str(e)}"
                health_status["status"] = "degraded"
        
        # Check session store
        try:
            await session_service.health_check()
            health_status["services"]["session_store"] = "healthy"
        except Exception as e:
            health_status["services"]["session_store"] = f"unhealthy: {str(e)}"
            health_status["status"] = "degraded"
        
        return health_status
        
    except Exception as e:
        logger.error(f"Auth health check error: {e}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }