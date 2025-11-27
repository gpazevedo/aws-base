"""Runner FastAPI service that calls the API service health endpoint."""

import logging
import os
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Any

import httpx
import structlog
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
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
    service_name: str = "runner"
    service_version: str = "0.1.0"
    environment: str = "dev"

    # HTTP client settings
    http_timeout: float = 30.0
    http_max_retries: int = 3

    # Observability settings
    enable_tracing: bool = True
    log_level: str = "INFO"
    otlp_endpoint: str = "http://localhost:4317"  # ADOT collector endpoint


settings = Settings()

# Track application startup time for uptime calculation
START_TIME = time.time()


# =============================================================================
# Logging Configuration
# =============================================================================


def configure_logging() -> None:
    """Configure structured logging with structlog."""
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.stdlib.filter_by_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    # Set log level from settings
    logging.basicConfig(
        format="%(message)s",
        level=getattr(logging, settings.log_level.upper()),
    )


# Configure logging on module import
configure_logging()
logger = structlog.get_logger()


# =============================================================================
# OpenTelemetry Configuration
# =============================================================================


def configure_tracing(app: FastAPI | None = None) -> None:
    """Configure OpenTelemetry tracing with ADOT."""
    logger.info(
        "tracing_configuration_starting",
        enable_tracing=settings.enable_tracing,
        is_test=bool(os.getenv("PYTEST_CURRENT_TEST")),
        app_provided=app is not None,
    )

    # Disable tracing during tests
    if os.getenv("PYTEST_CURRENT_TEST"):
        logger.info("tracing_disabled", reason="test_environment")
        return

    if settings.enable_tracing:
        logger.info("initializing_otel_components")

        # Create resource with service information
        resource = Resource.create(
            {
                "service.name": f"{settings.service_name}-{settings.environment}",
                "service.version": settings.service_version,
                "deployment.environment": settings.environment,
            }
        )
        logger.info("otel_resource_created")

        # Configure OTLP exporter to send traces to ADOT collector
        otlp_exporter = OTLPSpanExporter(
            endpoint=settings.otlp_endpoint,
            insecure=True,  # Use insecure for local ADOT collector
        )
        logger.info("otlp_exporter_created", endpoint=settings.otlp_endpoint)

        # Set up tracer provider with batch span processor
        provider = TracerProvider(resource=resource)
        processor = BatchSpanProcessor(otlp_exporter)
        provider.add_span_processor(processor)
        trace.set_tracer_provider(provider)
        logger.info("tracer_provider_configured")

        # Instrument HTTPX client for automatic tracing
        HTTPXClientInstrumentor().instrument()
        logger.info("httpx_instrumented")

        # Instrument FastAPI app if provided (called from lifespan)
        if app is not None:
            FastAPIInstrumentor.instrument_app(app)
            logger.info("fastapi_instrumented")

        logger.info(
            "tracing_configured",
            service=f"{settings.service_name}-{settings.environment}",
            otlp_endpoint=settings.otlp_endpoint,
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
    configure_tracing(app)

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

# Note: FastAPI instrumentation is now done in the lifespan startup
# to avoid event loop issues in Lambda/container environments


# =============================================================================
# Request Logging Middleware
# =============================================================================


@app.middleware("http")
async def logging_middleware(request: Request, call_next):
    """Log all HTTP requests with structured logging."""
    start_time = time.time()

    # Add request context to logs
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(
        path=request.url.path,
        method=request.method,
        client_ip=request.client.host if request.client else None,
    )

    logger.info(
        "request_started",
        path=request.url.path,
        method=request.method,
    )

    response = await call_next(request)

    duration = time.time() - start_time

    logger.info(
        "request_completed",
        path=request.url.path,
        method=request.method,
        status_code=response.status_code,
        duration_seconds=round(duration, 3),
    )

    return response


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
    return StatusResponse(status="alive")


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
