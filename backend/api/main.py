"""Main FastAPI application with health checks and example endpoints."""

import time
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from mangum import Mangum
from pydantic import BaseModel

# =============================================================================
# Application Configuration
# =============================================================================

app = FastAPI(
    title="AWS Base Python API",
    description="Production-ready FastAPI template for AWS Lambda",
    version="0.1.0",
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


class GreetingRequest(BaseModel):
    """Request model for greeting endpoint."""

    name: str


class GreetingResponse(BaseModel):
    """Response model for greeting endpoint."""

    message: str
    version: str


class StatusResponse(BaseModel):
    """Simple status response."""

    status: str


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

    Returns:
        HealthResponse: Health check data
    """
    uptime = time.time() - START_TIME
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat(),
        uptime_seconds=round(uptime, 2),
        version="0.1.0",
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
    Can be extended to check database connections, external services, etc.

    Returns:
        StatusResponse: Simple status indicating the app is ready
    """
    # Add your readiness checks here (database, cache, etc.)
    # For now, always return ready
    return StatusResponse(status="ready")


# =============================================================================
# API Endpoints
# =============================================================================


@app.get("/", response_model=GreetingResponse, tags=["General"])
async def root() -> GreetingResponse:
    """
    Root endpoint - simple welcome message.

    Returns:
        GreetingResponse: Welcome message with version
    """
    return GreetingResponse(message="Hello, World!", version="0.1.0")


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
    return GreetingResponse(message=f"Hello, {name}!", version="0.1.0")


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
    return GreetingResponse(message=f"Hello, {request.name}!", version="0.1.0")


@app.get("/error", tags=["General"])
async def trigger_error() -> None:
    """
    Endpoint to test error handling.

    Raises:
        HTTPException: Always raises a 500 error for testing
    """
    raise HTTPException(status_code=500, detail="This is a test error")


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
                "/greet",
                "/docs",
                "/redoc",
                "/openapi.json",
            ],
        },
    )


# =============================================================================
# Lambda Handler
# =============================================================================

# Mangum adapter to run FastAPI on AWS Lambda
handler = Mangum(app, lifespan="off")


# =============================================================================
# Local Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
