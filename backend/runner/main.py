"""
runner Service

runner service
"""

import os
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Query

from common import (
    configure_logging,
    get_logger,
    LoggingMiddleware,
    health_check_simple,
    HealthResponse,
    ServiceInfo,
    InterServiceResponse,
)

# =============================================================================
# Configuration
# =============================================================================

SERVICE_NAME = "runner"
SERVICE_VERSION = "1.0.0"
START_TIME = time.time()  # Unix timestamp for uptime calculation

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
PROJECT_NAME = os.getenv("PROJECT_NAME", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# App Runner port (must be 8080)
PORT = int(os.getenv("PORT", "8080"))

# =============================================================================
# Logging Setup
# =============================================================================

configure_logging(log_level=LOG_LEVEL)

# Get logger with service context
logger = get_logger(__name__).bind(
    service=SERVICE_NAME,
    environment=ENVIRONMENT,
)

# =============================================================================
# Application Lifecycle
# =============================================================================


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Manage application lifespan with proper resource cleanup.

    This modern FastAPI pattern replaces the deprecated @app.on_event decorators.
    Resources are initialized on startup and cleaned up on shutdown.
    """
    logger.info(
        "service_starting",
        service=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
        port=PORT,
    )

    # Initialize shared HTTP client for inter-service communication
    app.state.http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(30.0),
        limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
    )

    yield

    # Cleanup
    logger.info("service_stopping", service=SERVICE_NAME)
    await app.state.http_client.aclose()


# =============================================================================
# FastAPI Application
# =============================================================================

app = FastAPI(
    title=f"{SERVICE_NAME} Service",
    description="runner service",
    version=SERVICE_VERSION,
    lifespan=lifespan,
)

# Add middleware
app.add_middleware(LoggingMiddleware)


# =============================================================================
# Health Check Endpoints
# =============================================================================


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Simple health check endpoint"""
    return await health_check_simple(SERVICE_NAME, SERVICE_VERSION, START_TIME)


@app.get("/status", response_model=ServiceInfo)
async def status():
    """Detailed service status"""
    return ServiceInfo(
        name=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
        description="runner service",
    )


# =============================================================================
# Business Logic Endpoints
# =============================================================================


@app.get("/")
async def root():
    """Root endpoint"""
    logger.info("root_endpoint_called")
    return {
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "message": f"Welcome to {SERVICE_NAME} service",
    }


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
        GET /inter-service?service_url=https://example.com/health
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


# Add your business logic endpoints here
# Example:
# @app.post("/process")
# async def process_data(data: YourModel):
#     logger.info("processing_data", data=data.dict())
#     # Your business logic here
#     return {"status": "processed"}


# =============================================================================
# Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    logger.info("starting_dev_server", port=PORT)
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=PORT,
        reload=True,
        log_config=None,  # Use our custom logging
    )
