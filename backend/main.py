#!/usr/bin/env python3
"""
OCI IDCS SSO Platform - FastAPI Backend
Main application entry point
"""

import os
import sys
import logging
from contextlib import asynccontextmanager
from typing import Dict, Any

import uvicorn
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.security import HTTPBearer
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# Add the current directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.core.config import settings
from app.core.database import engine, database
from app.core.logging_config import setup_logging
from app.core.security import security_headers_middleware
from app.api.v1.api import api_router
from app.middleware.auth import AuthMiddleware
from app.middleware.request_id import RequestIDMiddleware
from app.middleware.error_handler import ErrorHandlerMiddleware
from app.services.health import HealthService
from app.services.metrics import MetricsService

# Setup logging
setup_logging()
logger = logging.getLogger(__name__)

# Rate limiter
limiter = Limiter(key_func=get_remote_address)

# Security
security = HTTPBearer(auto_error=False)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan manager
    """
    logger.info("Starting OCI IDCS SSO Platform...")
    
    try:
        # Connect to database
        await database.connect()
        logger.info("Database connected successfully")
        
        # Initialize services
        health_service = HealthService()
        metrics_service = MetricsService()
        
        # Perform startup checks
        await health_service.startup_check()
        logger.info("Startup health checks passed")
        
        # Initialize metrics
        if settings.METRICS_ENABLED:
            await metrics_service.initialize()
            logger.info("Metrics service initialized")
        
        logger.info("Application startup completed successfully")
        yield
        
    except Exception as e:
        logger.error(f"Failed to start application: {e}")
        raise
    finally:
        # Cleanup
        logger.info("Shutting down application...")
        await database.disconnect()
        logger.info("Database disconnected")
        logger.info("Application shutdown completed")


def create_app() -> FastAPI:
    """
    Create and configure FastAPI application
    """
    
    # Create FastAPI instance
    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        description="OCI IDCS와 OpenLDAP을 연동한 SSO 통합 플랫폼",
        openapi_url="/api/v1/openapi.json" if settings.DEBUG else None,
        docs_url="/docs" if settings.DEBUG else None,
        redoc_url="/redoc" if settings.DEBUG else None,
        lifespan=lifespan
    )
    
    # Configure CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ALLOW_ORIGINS,
        allow_credentials=settings.CORS_ALLOW_CREDENTIALS,
        allow_methods=settings.CORS_ALLOW_METHODS,
        allow_headers=settings.CORS_ALLOW_HEADERS,
    )
    
    # Add security headers
    app.add_middleware(security_headers_middleware)
    
    # Add trusted host middleware for production
    if not settings.DEBUG:
        app.add_middleware(
            TrustedHostMiddleware,
            allowed_hosts=[settings.APP_DOMAIN, f"*.{settings.APP_DOMAIN}"]
        )
    
    # Add compression middleware
    app.add_middleware(GZipMiddleware, minimum_size=1000)
    
    # Add custom middlewares
    app.add_middleware(RequestIDMiddleware)
    app.add_middleware(AuthMiddleware)
    app.add_middleware(ErrorHandlerMiddleware)
    
    # Rate limiting
    if settings.RATE_LIMIT_ENABLED:
        app.state.limiter = limiter
        app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    
    # Include API routes
    app.include_router(api_router, prefix="/api/v1")
    
    # Health check endpoint
    @app.get("/health")
    async def health_check():
        """Application health check"""
        health_service = HealthService()
        return await health_service.check_health()
    
    # Metrics endpoint
    if settings.METRICS_ENABLED:
        @app.get("/metrics")
        async def metrics():
            """Prometheus metrics endpoint"""
            metrics_service = MetricsService()
            return Response(
                content=await metrics_service.generate_metrics(),
                media_type="text/plain"
            )
    
    # Root endpoint
    @app.get("/")
    async def root():
        """Root endpoint"""
        return {
            "message": "OCI IDCS SSO Platform API",
            "version": settings.APP_VERSION,
            "status": "running",
            "docs": f"{settings.BACKEND_URL}/docs" if settings.DEBUG else None
        }
    
    # Global exception handler
    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception):
        """Global exception handler"""
        logger.error(f"Unhandled exception: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "error": "Internal server error",
                "message": "An unexpected error occurred",
                "request_id": getattr(request.state, "request_id", None)
            }
        )
    
    # Startup event
    @app.on_event("startup")
    async def startup_event():
        """Startup event handler"""
        logger.info(f"Starting {settings.APP_NAME} v{settings.APP_VERSION}")
        logger.info(f"Environment: {settings.ENVIRONMENT}")
        logger.info(f"Debug mode: {settings.DEBUG}")
    
    # Shutdown event
    @app.on_event("shutdown")
    async def shutdown_event():
        """Shutdown event handler"""
        logger.info("Application shutdown complete")
    
    return app


# Create application instance
app = create_app()


if __name__ == "__main__":
    """
    Run the application directly
    """
    log_level = "debug" if settings.DEBUG else "info"
    
    uvicorn.run(
        "main:app",
        host=settings.APP_HOST,
        port=settings.APP_PORT,
        reload=settings.DEBUG,
        log_level=log_level,
        access_log=True,
        ssl_keyfile=settings.SSL_KEY_PATH if settings.SSL_ENABLED else None,
        ssl_certfile=settings.SSL_CERT_PATH if settings.SSL_ENABLED else None,
        workers=1 if settings.DEBUG else 4,
    )