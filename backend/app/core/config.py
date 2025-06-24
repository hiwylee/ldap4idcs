#!/usr/bin/env python3
"""
Application configuration settings
"""

import os
import json
from typing import List, Dict, Any, Optional
from pydantic import BaseSettings, validator, Field


class Settings(BaseSettings):
    """
    Application settings configuration
    """
    
    # =================================================================
    # Application Settings
    # =================================================================
    APP_NAME: str = "OCI IDCS SSO Platform"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    DEBUG: bool = True
    LOG_LEVEL: str = "INFO"
    
    APP_HOST: str = "0.0.0.0"
    APP_PORT: int = 8000
    FRONTEND_URL: str = "http://localhost:3000"
    BACKEND_URL: str = "http://localhost:8000"
    APP_DOMAIN: str = "localhost"
    
    # =================================================================
    # Database Configuration
    # =================================================================
    DATABASE_URL: str = "postgresql://sso_user:sso_password@localhost:5432/sso_db"
    DATABASE_POOL_SIZE: int = 10
    DATABASE_MAX_OVERFLOW: int = 20
    DATABASE_POOL_TIMEOUT: int = 30
    
    # Redis Configuration
    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_SESSION_DB: int = 1
    REDIS_CACHE_DB: int = 2
    REDIS_PASSWORD: Optional[str] = None
    
    # =================================================================
    # JWT Configuration
    # =================================================================
    JWT_SECRET_KEY: str = "your-super-secret-jwt-key-change-this-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 480
    JWT_REFRESH_EXPIRE_DAYS: int = 7
    JWT_ISSUER: str = "oci-idcs-sso-platform"
    
    # =================================================================
    # OCI IDCS Configuration
    # =================================================================
    IDCS_TENANT_URL: str = "https://idcs-xxxxxxxxxxxx.identity.oraclecloud.com"
    IDCS_CLIENT_ID: str = ""
    IDCS_CLIENT_SECRET: str = ""
    IDCS_SCOPE: str = "openid profile email groups"
    IDCS_RESPONSE_TYPE: str = "code"
    IDCS_REDIRECT_URI: str = "http://localhost:8000/api/auth/oauth/callback"
    IDCS_POST_LOGOUT_REDIRECT_URI: str = "http://localhost:3000/login"
    
    # IDCS API Configuration
    IDCS_API_VERSION: str = "v1"
    IDCS_API_TIMEOUT: int = 30
    IDCS_TOKEN_ENDPOINT: str = "/oauth2/v1/token"
    IDCS_USERINFO_ENDPOINT: str = "/oauth2/v1/userinfo"
    IDCS_JWKS_ENDPOINT: str = "/oauth2/v1/keys"
    
    # =================================================================
    # SAML Configuration
    # =================================================================
    SAML_ENTITY_ID: str = "http://localhost:8000/api/auth/saml/metadata"
    SAML_ACS_URL: str = "http://localhost:8000/api/auth/saml/acs"
    SAML_SLO_URL: str = "http://localhost:8000/api/auth/saml/sls"
    SAML_METADATA_URL: str = "http://localhost:8000/api/auth/saml/metadata"
    
    # SAML Identity Provider (IDCS)
    SAML_IDP_ENTITY_ID: str = ""
    SAML_IDP_SSO_URL: str = ""
    SAML_IDP_SLO_URL: str = ""
    SAML_IDP_METADATA_URL: str = ""
    
    # SAML Security Settings
    SAML_SIGN_REQUESTS: bool = True
    SAML_SIGN_ASSERTIONS: bool = True
    SAML_ENCRYPT_ASSERTIONS: bool = False
    SAML_WANT_ASSERTIONS_SIGNED: bool = True
    SAML_WANT_RESPONSE_SIGNED: bool = True
    SAML_SIGNATURE_ALGORITHM: str = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
    SAML_DIGEST_ALGORITHM: str = "http://www.w3.org/2001/04/xmlenc#sha256"
    
    # SAML Certificates
    SAML_X509_CERT: str = ""
    SAML_PRIVATE_KEY: str = ""
    
    # =================================================================
    # LDAP Configuration
    # =================================================================
    LDAP_SERVER: str = "ldap://localhost:389"
    LDAP_USE_SSL: bool = False
    LDAP_USE_TLS: bool = False
    LDAP_SSL_VERSION: str = "TLSv1_2"
    LDAP_CERT_FILE: str = ""
    LDAP_KEY_FILE: str = ""
    LDAP_CA_CERT_FILE: str = ""
    
    # LDAP Bind Configuration
    LDAP_BIND_DN: str = "cn=admin,dc=company,dc=com"
    LDAP_BIND_PASSWORD: str = "admin_password"
    
    # LDAP Directory Structure
    LDAP_BASE_DN: str = "dc=company,dc=com"
    LDAP_USER_DN: str = "ou=users,dc=company,dc=com"
    LDAP_GROUP_DN: str = "ou=groups,dc=company,dc=com"
    LDAP_APPLICATION_DN: str = "ou=applications,dc=company,dc=com"
    
    # LDAP Search Settings
    LDAP_USER_FILTER: str = "(uid={username})"
    LDAP_GROUP_FILTER: str = "(cn={groupname})"
    LDAP_USER_SEARCH_SCOPE: str = "SUBTREE"
    LDAP_GROUP_SEARCH_SCOPE: str = "SUBTREE"
    
    # LDAP Attributes Mapping
    LDAP_USER_ID_ATTR: str = "uid"
    LDAP_USER_EMAIL_ATTR: str = "mail"
    LDAP_USER_FIRST_NAME_ATTR: str = "givenName"
    LDAP_USER_LAST_NAME_ATTR: str = "sn"
    LDAP_USER_DISPLAY_NAME_ATTR: str = "displayName"
    LDAP_GROUP_NAME_ATTR: str = "cn"
    LDAP_GROUP_MEMBER_ATTR: str = "member"
    
    # LDAP Connection Pool
    LDAP_POOL_SIZE: int = 10
    LDAP_POOL_MAX_SIZE: int = 20
    LDAP_POOL_TIMEOUT: int = 30
    
    # =================================================================
    # LDAP ↔ IDCS Synchronization
    # =================================================================
    SYNC_ENABLED: bool = True
    SYNC_INTERVAL_HOURS: int = 1
    SYNC_BATCH_SIZE: int = 100
    SYNC_DELETE_MISSING_USERS: bool = False
    SYNC_DELETE_MISSING_GROUPS: bool = False
    SYNC_DRY_RUN: bool = False
    
    # Synchronization Mapping
    SYNC_USER_MAPPING: str = "uid:userName,mail:emails[0].value,givenName:name.givenName,sn:name.familyName"
    SYNC_GROUP_MAPPING: str = "cn:displayName,description:description"
    
    # =================================================================
    # Session Management
    # =================================================================
    SESSION_COOKIE_NAME: str = "sso_session"
    SESSION_COOKIE_DOMAIN: str = ""
    SESSION_COOKIE_PATH: str = "/"
    SESSION_COOKIE_SECURE: bool = False
    SESSION_COOKIE_HTTPONLY: bool = True
    SESSION_COOKIE_SAMESITE: str = "Lax"
    SESSION_EXPIRE_SECONDS: int = 28800
    SESSION_REFRESH_THRESHOLD: int = 1800
    
    # =================================================================
    # Security Settings
    # =================================================================
    # CORS Settings
    CORS_ALLOW_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:8000"]
    CORS_ALLOW_CREDENTIALS: bool = True
    CORS_ALLOW_METHODS: List[str] = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    CORS_ALLOW_HEADERS: List[str] = ["*"]
    
    # Rate Limiting
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_REQUESTS_PER_MINUTE: int = 60
    RATE_LIMIT_BURST: int = 10
    
    # Password Policy
    PASSWORD_MIN_LENGTH: int = 8
    PASSWORD_REQUIRE_UPPERCASE: bool = True
    PASSWORD_REQUIRE_LOWERCASE: bool = True
    PASSWORD_REQUIRE_NUMBERS: bool = True
    PASSWORD_REQUIRE_SPECIAL: bool = True
    PASSWORD_MAX_AGE_DAYS: int = 90
    
    # Account Lockout Policy
    ACCOUNT_LOCKOUT_ENABLED: bool = True
    ACCOUNT_LOCKOUT_THRESHOLD: int = 5
    ACCOUNT_LOCKOUT_DURATION_MINUTES: int = 30
    
    # =================================================================
    # SSL/TLS Configuration
    # =================================================================
    SSL_ENABLED: bool = False
    SSL_CERT_PATH: str = "/app/ssl/server.crt"
    SSL_KEY_PATH: str = "/app/ssl/server.key"
    SSL_CA_PATH: str = "/app/ssl/ca.crt"
    SSL_VERIFY_MODE: str = "CERT_REQUIRED"
    
    # =================================================================
    # External Applications Configuration
    # =================================================================
    EXTERNAL_APPS: str = "[]"
    
    # =================================================================
    # Logging Configuration
    # =================================================================
    LOG_FORMAT: str = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    LOG_DATE_FORMAT: str = "%Y-%m-%d %H:%M:%S"
    LOG_FILE_PATH: str = "/app/logs/app.log"
    LOG_MAX_SIZE_MB: int = 10
    LOG_BACKUP_COUNT: int = 5
    LOG_ROTATION: str = "time"
    
    # Specific Loggers
    LDAP_LOG_LEVEL: str = "INFO"
    IDCS_LOG_LEVEL: str = "INFO"
    AUTH_LOG_LEVEL: str = "INFO"
    SYNC_LOG_LEVEL: str = "INFO"
    
    # =================================================================
    # Monitoring and Health Check
    # =================================================================
    HEALTH_CHECK_ENABLED: bool = True
    HEALTH_CHECK_TIMEOUT: int = 5
    METRICS_ENABLED: bool = True
    METRICS_PORT: int = 9000
    
    # =================================================================
    # Email Configuration
    # =================================================================
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_USE_TLS: bool = True
    SMTP_FROM_EMAIL: str = "noreply@company.com"
    SMTP_FROM_NAME: str = "SSO Platform"
    
    # =================================================================
    # Feature Flags
    # =================================================================
    FEATURE_LDAP_SYNC: bool = True
    FEATURE_OAUTH_LOGIN: bool = True
    FEATURE_SAML_LOGIN: bool = True
    FEATURE_DIRECT_LDAP_LOGIN: bool = True
    FEATURE_MULTI_TENANT: bool = False
    FEATURE_ADVANCED_AUDIT: bool = False
    
    # =================================================================
    # Validators
    # =================================================================
    
    @validator('CORS_ALLOW_ORIGINS', pre=True)
    def validate_cors_origins(cls, v):
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(',')]
        return v
    
    @validator('CORS_ALLOW_METHODS', pre=True)
    def validate_cors_methods(cls, v):
        if isinstance(v, str):
            return [method.strip() for method in v.split(',')]
        return v
    
    @validator('CORS_ALLOW_HEADERS', pre=True)
    def validate_cors_headers(cls, v):
        if isinstance(v, str):
            return [header.strip() for header in v.split(',')]
        return v
    
    @validator('EXTERNAL_APPS', pre=True)
    def validate_external_apps(cls, v):
        if isinstance(v, str):
            try:
                return json.loads(v)
            except json.JSONDecodeError:
                return []
        return v
    
    @validator('JWT_SECRET_KEY')
    def validate_jwt_secret_key(cls, v):
        if len(v) < 32:
            raise ValueError('JWT_SECRET_KEY must be at least 32 characters long')
        return v
    
    @validator('DATABASE_URL')
    def validate_database_url(cls, v):
        if not v.startswith(('postgresql://', 'postgresql+asyncpg://')):
            raise ValueError('DATABASE_URL must be a PostgreSQL connection string')
        return v
    
    @validator('REDIS_URL')
    def validate_redis_url(cls, v):
        if not v.startswith('redis://'):
            raise ValueError('REDIS_URL must be a Redis connection string')
        return v
    
    @validator('LDAP_SERVER')
    def validate_ldap_server(cls, v):
        if not v.startswith(('ldap://', 'ldaps://')):
            raise ValueError('LDAP_SERVER must start with ldap:// or ldaps://')
        return v
    
    @validator('IDCS_TENANT_URL')
    def validate_idcs_tenant_url(cls, v):
        if v and not v.startswith('https://'):
            raise ValueError('IDCS_TENANT_URL must start with https://')
        return v
    
    # =================================================================
    # Computed Properties
    # =================================================================
    
    @property
    def is_production(self) -> bool:
        """Check if running in production environment"""
        return self.ENVIRONMENT.lower() == "production"
    
    @property
    def is_development(self) -> bool:
        """Check if running in development environment"""
        return self.ENVIRONMENT.lower() == "development"
    
    @property
    def idcs_authorization_url(self) -> str:
        """Get IDCS OAuth authorization URL"""
        if not self.IDCS_TENANT_URL:
            return ""
        return f"{self.IDCS_TENANT_URL}/oauth2/v1/authorize"
    
    @property
    def idcs_token_url(self) -> str:
        """Get IDCS OAuth token URL"""
        if not self.IDCS_TENANT_URL:
            return ""
        return f"{self.IDCS_TENANT_URL}{self.IDCS_TOKEN_ENDPOINT}"
    
    @property
    def idcs_userinfo_url(self) -> str:
        """Get IDCS userinfo URL"""
        if not self.IDCS_TENANT_URL:
            return ""
        return f"{self.IDCS_TENANT_URL}{self.IDCS_USERINFO_ENDPOINT}"
    
    @property
    def idcs_jwks_url(self) -> str:
        """Get IDCS JWKS URL"""
        if not self.IDCS_TENANT_URL:
            return ""
        return f"{self.IDCS_TENANT_URL}{self.IDCS_JWKS_ENDPOINT}"
    
    @property
    def redis_session_url(self) -> str:
        """Get Redis session database URL"""
        base_url = self.REDIS_URL.split('/')[0] + '//' + self.REDIS_URL.split('//')[1].split('/')[0]
        return f"{base_url}/{self.REDIS_SESSION_DB}"
    
    @property
    def redis_cache_url(self) -> str:
        """Get Redis cache database URL"""
        base_url = self.REDIS_URL.split('/')[0] + '//' + self.REDIS_URL.split('//')[1].split('/')[0]
        return f"{base_url}/{self.REDIS_CACHE_DB}"
    
    @property
    def external_apps_config(self) -> List[Dict[str, Any]]:
        """Get parsed external applications configuration"""
        if isinstance(self.EXTERNAL_APPS, str):
            try:
                return json.loads(self.EXTERNAL_APPS)
            except json.JSONDecodeError:
                return []
        return self.EXTERNAL_APPS
    
    @property
    def sync_user_mapping_dict(self) -> Dict[str, str]:
        """Get parsed user mapping for synchronization"""
        mapping = {}
        if self.SYNC_USER_MAPPING:
            for pair in self.SYNC_USER_MAPPING.split(','):
                if ':' in pair:
                    ldap_attr, idcs_attr = pair.strip().split(':', 1)
                    mapping[ldap_attr.strip()] = idcs_attr.strip()
        return mapping
    
    @property
    def sync_group_mapping_dict(self) -> Dict[str, str]:
        """Get parsed group mapping for synchronization"""
        mapping = {}
        if self.SYNC_GROUP_MAPPING:
            for pair in self.SYNC_GROUP_MAPPING.split(','):
                if ':' in pair:
                    ldap_attr, idcs_attr = pair.strip().split(':', 1)
                    mapping[ldap_attr.strip()] = idcs_attr.strip()
        return mapping
    
    class Config:
        """Pydantic configuration"""
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


# Global settings instance
settings = Settings()