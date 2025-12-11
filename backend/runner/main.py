"""Runner FastAPI service that calls the API service health endpoint."""

import os
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from shared import (
    ErrorResponse,
    FullServiceSettings,
    GreetingRequest,
    GreetingResponse,
    LoggingMiddleware,
    StatusResponse,
    configure_logging,
    configure_tracing,
    get_logger,
    liveness_probe_simple,
)

# =============================================================================
# Configuration
# =============================================================================


class Settings(FullServiceSettings):
    """Application settings loaded from environment variables."""

    # API service URL (must be set via environment variable)
    api_service_url: str = "http://localhost:8000"

    # Service configuration (inherited from FullServiceSettings)
    service_name: str = "runner"
    service_version: str = "0.1.0"

    # HTTP client settings (inherited and extended)
    http_max_retries: int = 3


settings = Settings()

# Track application startup time for uptime calculation
START_TIME = time.time()


# =============================================================================
# Logging Configuration
# =============================================================================

# Configure logging from shared library
configure_logging(log_level=settings.log_level)
logger = get_logger(__name__)


# =============================================================================
# Application Lifespan
# =============================================================================


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """
    Manage application lifespan with proper resource cleanup.

    This modern FastAPI pattern replaces the deprecated @app.on_event decorators.
    Resources are initialized on startup and cleaned up on shutdown.
    """
    logger.info(
        "lifespan_startup_begin",
        is_lambda=bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME")),
        aws_execution_env=os.getenv("AWS_EXECUTION_ENV", "not_set"),
    )

    # Startup: Configure tracing and initialize shared HTTP client
    configure_tracing(
        service_name=settings.service_name,
        service_version=settings.service_version,
        environment=settings.environment,
        app=app,
    )

    logger.info(
        "application_startup",
        service=settings.service_name,
        version=settings.service_version,
        environment=settings.environment,
        api_service_url=settings.api_service_url,
    )

    app.state.http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(settings.http_timeout),
        limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
    )

    yield  # Application runs here

    # Shutdown: Clean up resources
    logger.info("application_shutdown", service=settings.service_name)
    await app.state.http_client.aclose()


# =============================================================================
# Application Configuration
# =============================================================================

app = FastAPI(
    title="AWS Runner Service",
    description="Runner service that calls the API service health endpoint",
    version=settings.service_version,
    docs_url="/docs",  # Swagger UI
    redoc_url="/redoc",  # ReDoc
    openapi_url="/openapi.json",  # OpenAPI schema
    lifespan=lifespan,
)

# Add logging middleware from shared library
app.add_middleware(LoggingMiddleware)


# =============================================================================
# Pydantic Models
# =============================================================================


class HealthResponse(BaseModel):
    """Health check response model."""

    status: str
    timestamp: str
    uptime_seconds: float
    version: str
    service_name: str


class ApiHealthResponse(BaseModel):
    """Response from calling API service health endpoint."""

    api_response: dict[str, Any]
    status_code: int
    response_time_ms: float


# =============================================================================
# Health Check Endpoints
# =============================================================================


@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check() -> HealthResponse:
    """
    Comprehensive health check endpoint.

    Returns detailed information about the application status including:
    - Current status
    - Server timestamp
    - Uptime in seconds
    - Application version
    - Service name

    Returns:
        HealthResponse: Health check data
    """
    from datetime import UTC, datetime

    uptime = time.time() - START_TIME
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(UTC).isoformat(),
        uptime_seconds=round(uptime, 2),
        version=settings.service_version,
        service_name=settings.service_name,
    )


@app.get("/liveness", response_model=StatusResponse, tags=["Health"])
async def liveness_probe() -> StatusResponse:
    """
    Kubernetes-style liveness probe.

    Indicates whether the application is running.
    Returns 200 if the app is alive, otherwise the container should be restarted.

    Returns:
        StatusResponse: Simple status indicating the app is alive
    """
    return await liveness_probe_simple()


@app.get("/readiness", response_model=StatusResponse, tags=["Health"])
async def readiness_probe() -> StatusResponse:
    """
    Kubernetes-style readiness probe.

    Indicates whether the application is ready to receive traffic.
    Checks if we can reach the API service using the shared HTTP client.

    Returns:
        StatusResponse: Simple status indicating the app is ready

    Raises:
        HTTPException: If the API service is unreachable
    """
    # Check if we can reach the API service
    try:
        # Use shared HTTP client with short timeout for readiness check
        response = await app.state.http_client.get(
            f"{settings.api_service_url}/health",
            timeout=5.0,
        )
        if response.status_code == 200:
            logger.debug("readiness_check_passed", api_service_url=settings.api_service_url)
            return StatusResponse(status="ready")
        else:
            logger.warning(
                "readiness_check_failed",
                api_service_url=settings.api_service_url,
                status_code=response.status_code,
            )
            raise HTTPException(
                status_code=503,
                detail=f"API service returned status {response.status_code}",
            )
    except httpx.RequestError as e:
        logger.error(
            "readiness_check_error",
            api_service_url=settings.api_service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=503,
            detail=f"Cannot reach API service: {str(e)}",
        ) from e


# =============================================================================
# API Service Integration Endpoints
# =============================================================================


@app.get("/api-health", response_model=ApiHealthResponse, tags=["API Integration"])
async def get_api_health() -> ApiHealthResponse:
    """
    Call the API service health endpoint and return the response.

    This endpoint demonstrates service-to-service communication by calling
    the API service's /health endpoint and returning what it received.

    Returns:
        ApiHealthResponse: The response from the API service including
                          status code, response time, and the full response body

    Raises:
        HTTPException: If the API service is unreachable or returns an error
    """
    start_time = time.time()

    logger.info("calling_api_service_health", api_service_url=settings.api_service_url)

    try:
        # Use shared HTTP client from app.state (initialized in lifespan)
        response = await app.state.http_client.get(f"{settings.api_service_url}/health")
        response_time = (time.time() - start_time) * 1000  # Convert to ms

        logger.info(
            "api_service_health_response",
            api_service_url=settings.api_service_url,
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
        )

        # Return the response regardless of status code
        return ApiHealthResponse(
            api_response=response.json(),
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
        )
    except httpx.RequestError as e:
        logger.error(
            "api_service_health_request_error",
            api_service_url=settings.api_service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=503,
            detail=f"Failed to reach API service: {str(e)}",
        ) from e
    except Exception as e:
        logger.exception(
            "api_service_health_unexpected_error",
            api_service_url=settings.api_service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error calling API service: {str(e)}",
        ) from e


# =============================================================================
# General API Endpoints
# =============================================================================


@app.get("/", response_model=GreetingResponse, tags=["General"])
async def root() -> GreetingResponse:
    """
    Root endpoint - simple welcome message.

    Returns:
        GreetingResponse: Welcome message with version
    """
    return GreetingResponse(
        message=f"Hello from {settings.service_name}!",
        version=settings.service_version,
    )


@app.get("/greet", response_model=GreetingResponse, tags=["General"])
async def greet(
    name: str = Query(default="World", description="Name to greet"),
) -> GreetingResponse:
    """
    Greet a person by name.

    Args:
        name: The name to greet (query parameter)

    Returns:
        GreetingResponse: Personalized greeting message

    Example:
        GET /greet?name=Alice
        Response: {"message": "Hello, Alice!", "version": "0.1.0"}
    """
    return GreetingResponse(
        message=f"Hello, {name}! (from {settings.service_name})",
        version=settings.service_version,
    )


@app.post("/greet", response_model=GreetingResponse, tags=["General"])
async def greet_post(request: GreetingRequest) -> GreetingResponse:
    """
    Greet a person by name (POST version).

    Args:
        request: GreetingRequest with name in body

    Returns:
        GreetingResponse: Personalized greeting message

    Example:
        POST /greet
        Body: {"name": "Alice"}
        Response: {"message": "Hello, Alice!", "version": "0.1.0"}
    """
    return GreetingResponse(
        message=f"Hello, {request.name}! (from {settings.service_name})",
        version=settings.service_version,
    )


@app.get("/error", tags=["General"])
async def trigger_error() -> None:
    """
    Endpoint to test error handling.

    Raises:
        HTTPException: Always raises a 500 error for testing
    """
    raise HTTPException(status_code=500, detail="This is a test error from Runner service")


# =============================================================================
# Exception Handlers
# =============================================================================


@app.exception_handler(404)
async def not_found_handler(request: Any, exc: Any) -> JSONResponse:
    """Custom 404 handler."""
    return JSONResponse(
        status_code=404,
        content={
            "error": "Not Found",
            "message": f"The path {request.url.path} was not found",
            "available_endpoints": [
                "/",
                "/health",
                "/liveness",
                "/readiness",
                "/api-health",
                "/greet",
                "/docs",
                "/redoc",
                "/openapi.json",
            ],
        },
    )


# =============================================================================
# Local Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8080,
        log_level="info",
    )
