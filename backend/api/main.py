"""Main FastAPI application with health checks and example endpoints."""

import asyncio
import os
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from mangum import Mangum
from shared import (
    FullServiceSettings,
    GreetingRequest,
    GreetingResponse,
    HealthResponse,
    InterServiceResponse,
    LoggingMiddleware,
    StatusResponse,
    configure_logging,
    configure_tracing,
    get_logger,
    health_check_simple,
    liveness_probe_simple,
    readiness_probe_simple,
)

# =============================================================================
# Configuration
# =============================================================================


class Settings(FullServiceSettings):
    """Application settings loaded from environment variables."""

    # Service configuration (inherited from FullServiceSettings)
    service_name: str = "api"
    service_version: str = "0.1.0"


settings = Settings()

# Track application startup time for uptime calculation
START_TIME = time.time()


# =============================================================================
# Logging Configuration
# =============================================================================

# Configure logging from shared library
configure_logging(log_level=settings.log_level)
logger = get_logger(__name__)

# Log module initialization to verify deployment
logger.info(
    "module_initialization",
    service_version=settings.service_version,
    is_lambda=bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME")),
)


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
    title="AWS Base Python API",
    description="Production-ready FastAPI template for AWS Lambda",
    version=settings.service_version,
    docs_url="/docs",  # Swagger UI
    redoc_url="/redoc",  # ReDoc
    openapi_url="/openapi.json",  # OpenAPI schema
    lifespan=lifespan,
)

# Add logging middleware from shared library
app.add_middleware(LoggingMiddleware)


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
    return await health_check_simple(settings.service_version, START_TIME)


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
    Can be extended to check database connections, external services, etc.

    Returns:
        StatusResponse: Simple status indicating the app is ready
    """
    return await readiness_probe_simple()


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
    return GreetingResponse(message="Hello, World!", version=settings.service_version)


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
        Response: {"message": "Hello, Alice!", "version": "0.2.0"}
    """
    return GreetingResponse(message=f"Hello, {name}!", version=settings.service_version)


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
        Response: {"message": "Hello, Alice!", "version": "0.2.0"}
    """
    return GreetingResponse(message=f"Hello, {request.name}!", version=settings.service_version)


@app.get("/error", tags=["General"])
async def trigger_error() -> None:
    """
    Endpoint to test error handling.

    Raises:
        HTTPException: Always raises a 500 error for testing
    """
    raise HTTPException(status_code=500, detail="This is a test error")


# =============================================================================
# Inter-Service Communication Endpoints
# =============================================================================


@app.get("/inter-service", response_model=InterServiceResponse, tags=["Service Integration"])
async def call_service(
    service_url: str = Query(
        ...,
        description="Full URL of the service endpoint to call (e.g., https://example.com/health)",
    ),
) -> InterServiceResponse:
    """
    Call another service's endpoint and return the response.

    This endpoint demonstrates service-to-service communication by calling
    any provided service URL and returning what it received.
    Uses the shared HTTP client from app.state for connection pooling.

    Args:
        service_url: Full URL of the service endpoint to call (query parameter)

    Returns:
        InterServiceResponse: The response from the target service including
                             status code, response time, and the full response body

    Raises:
        HTTPException: If the target service is unreachable or returns an error

    Example:
        GET /inter-service?service_url=https://m269wkmi93.us-east-1.awsapprunner.com/health
    """
    start_time = time.time()

    logger.info("calling_external_service", target_url=service_url)

    try:
        # Use shared HTTP client from app.state (initialized in lifespan)
        response = await app.state.http_client.get(service_url)
        response_time = (time.time() - start_time) * 1000  # Convert to ms

        logger.info(
            "external_service_response",
            target_url=service_url,
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
        )

        # Return the response regardless of status code
        return InterServiceResponse(
            service_response=response.json(),
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
            target_url=service_url,
        )
    except httpx.RequestError as e:
        logger.error(
            "external_service_request_error",
            target_url=service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=503,
            detail=f"Failed to reach service at {service_url}: {str(e)}",
        ) from e
    except Exception as e:
        logger.exception(
            "external_service_unexpected_error",
            target_url=service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error calling service at {service_url}: {str(e)}",
        ) from e


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
                "/inter-service",
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
# Python 3.14 compatibility: Explicitly manage event loop for Lambda


def handler(event, context):
    """
    AWS Lambda handler with Python 3.14 asyncio compatibility.

    Python 3.14 removed the implicit event loop from asyncio.get_event_loop().
    We need to explicitly create and set an event loop for Mangum to work.

    Performance optimization: HTTP client is reused across warm Lambda invocations
    when the event loop is the same. If the loop changes, the client is recreated
    to avoid "bound to a different event loop" errors.
    """
    # Get or create event loop - reuse existing loop from warm container if available
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        # No running loop - create and set a new one
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    # Store the loop ID to detect when Lambda creates a new loop
    current_loop_id = id(asyncio.get_event_loop())

    # Initialize or recreate HTTP client if loop changed
    if (
        not hasattr(app.state, "http_client")
        or not hasattr(app.state, "_loop_id")
        or app.state._loop_id != current_loop_id
    ):
        # Clean up old client if it exists
        if hasattr(app.state, "http_client"):
            try:
                # Close old client (async operation, so run in the current loop)
                asyncio.get_event_loop().run_until_complete(app.state.http_client.aclose())
            except Exception:
                pass  # Ignore errors from closing stale client

        # Create new HTTP client bound to current event loop
        app.state.http_client = httpx.AsyncClient(
            timeout=httpx.Timeout(settings.http_timeout),
            limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
        )
        app.state._loop_id = current_loop_id

    # Create Mangum handler with the app (lifespan="off" to avoid double initialization)
    mangum_handler = Mangum(app, lifespan="off")
    return mangum_handler(event, context)

    # Note: Event loop and HTTP client are NOT closed here
    # They will be reused across Lambda invocations when the loop stays the same
    # Lambda runtime will clean them up when the container is terminated


# =============================================================================
# Local Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
