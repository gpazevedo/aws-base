"""AppRunner FastAPI service that calls the API service health endpoint."""

import time
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict


# =============================================================================
# Configuration
# =============================================================================


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # API service URL (must be set via environment variable)
    api_service_url: str = "http://localhost:8000"

    # Service configuration
    service_name: str = "apprunner"
    service_version: str = "0.1.0"

    # HTTP client settings
    http_timeout: float = 30.0
    http_max_retries: int = 3


settings = Settings()


# =============================================================================
# Application Configuration
# =============================================================================

app = FastAPI(
    title="AWS AppRunner Service",
    description="AppRunner service that calls the API service health endpoint",
    version=settings.service_version,
    docs_url="/docs",  # Swagger UI
    redoc_url="/redoc",  # ReDoc
    openapi_url="/openapi.json",  # OpenAPI schema
)

# Track application startup time for uptime calculation
START_TIME = time.time()


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


class StatusResponse(BaseModel):
    """Simple status response."""

    status: str


class GreetingRequest(BaseModel):
    """Request model for greeting endpoint."""

    name: str


class GreetingResponse(BaseModel):
    """Response model for greeting endpoint."""

    message: str
    version: str


class ErrorResponse(BaseModel):
    """Error response model."""

    error: str
    detail: str | None = None


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
    uptime = time.time() - START_TIME
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat(),
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
    return StatusResponse(status="alive")


@app.get("/readiness", response_model=StatusResponse, tags=["Health"])
async def readiness_probe() -> StatusResponse:
    """
    Kubernetes-style readiness probe.

    Indicates whether the application is ready to receive traffic.
    Checks if we can reach the API service.

    Returns:
        StatusResponse: Simple status indicating the app is ready

    Raises:
        HTTPException: If the API service is unreachable
    """
    # Check if we can reach the API service
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{settings.api_service_url}/health")
            if response.status_code == 200:
                return StatusResponse(status="ready")
            else:
                raise HTTPException(
                    status_code=503,
                    detail=f"API service returned status {response.status_code}",
                )
    except httpx.RequestError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Cannot reach API service: {str(e)}",
        )


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

    try:
        async with httpx.AsyncClient(timeout=settings.http_timeout) as client:
            response = await client.get(f"{settings.api_service_url}/health")
            response_time = (time.time() - start_time) * 1000  # Convert to ms

            # Return the response regardless of status code
            return ApiHealthResponse(
                api_response=response.json(),
                status_code=response.status_code,
                response_time_ms=round(response_time, 2),
            )
    except httpx.RequestError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Failed to reach API service: {str(e)}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error calling API service: {str(e)}",
        )


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
async def greet(name: str = Query(default="World", description="Name to greet")) -> GreetingResponse:
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
    raise HTTPException(status_code=500, detail="This is a test error from AppRunner service")


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
