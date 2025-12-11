"""Health check utilities for FastAPI services."""

import time
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime

from .models import HealthResponse, StatusResponse


def create_health_endpoint(
    service_name: str,
    service_version: str,
    start_time: float,
) -> Callable[[], Awaitable[HealthResponse]]:
    """
    Create a comprehensive health check endpoint function.

    Args:
        service_name: Name of the service
        service_version: Version of the service
        start_time: Service start time (from time.time())

    Returns:
        Async function that returns HealthResponse

    Example:
        >>> from shared.health import create_health_endpoint
        >>> import time
        >>> START_TIME = time.time()
        >>> @app.get("/health")
        >>> async def health():
        ...     return create_health_endpoint("api", "1.0.0", START_TIME)()
    """

    async def health_check() -> HealthResponse:
        uptime = time.time() - start_time
        return HealthResponse(
            status="healthy",
            timestamp=datetime.now(UTC).isoformat(),
            uptime_seconds=round(uptime, 2),
            version=service_version,
        )

    return health_check


def create_liveness_endpoint() -> Callable[[], Awaitable[StatusResponse]]:
    """
    Create a Kubernetes-style liveness probe endpoint.

    Returns:
        Async function that returns StatusResponse

    Example:
        >>> from shared.health import create_liveness_endpoint
        >>> @app.get("/liveness")
        >>> async def liveness():
        ...     return create_liveness_endpoint()()
    """

    async def liveness_probe() -> StatusResponse:
        return StatusResponse(status="alive")

    return liveness_probe


def create_readiness_endpoint(
    check_fn: Callable[[], bool] | None = None,
) -> Callable[[], Awaitable[StatusResponse]]:
    """
    Create a Kubernetes-style readiness probe endpoint.

    Args:
        check_fn: Optional function to perform readiness checks
                 Should return True if ready, False otherwise

    Returns:
        Async function that returns StatusResponse

    Example:
        >>> from shared.health import create_readiness_endpoint
        >>> def check_database():
        ...     return db.is_connected()
        >>> @app.get("/readiness")
        >>> async def readiness():
        ...     return create_readiness_endpoint(check_database)()
    """

    async def readiness_probe() -> StatusResponse:
        if check_fn and not check_fn():
            from fastapi import HTTPException

            raise HTTPException(status_code=503, detail="Service not ready")

        return StatusResponse(status="ready")

    return readiness_probe


# Simplified direct functions for common use cases


async def health_check_simple(
    service_version: str,
    start_time: float,
) -> HealthResponse:
    """
    Simple health check function (direct use).

    Args:
        service_version: Service version
        start_time: Service start time

    Returns:
        HealthResponse

    Example:
        >>> from shared.health import health_check_simple
        >>> import time
        >>> START_TIME = time.time()
        >>> @app.get("/health")
        >>> async def health():
        ...     return await health_check_simple("1.0.0", START_TIME)
    """
    uptime = time.time() - start_time
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(UTC).isoformat(),
        uptime_seconds=round(uptime, 2),
        version=service_version,
    )


async def liveness_probe_simple() -> StatusResponse:
    """
    Simple liveness probe (direct use).

    Example:
        >>> from shared.health import liveness_probe_simple
        >>> @app.get("/liveness")
        >>> async def liveness():
        ...     return await liveness_probe_simple()
    """
    return StatusResponse(status="alive")


async def readiness_probe_simple() -> StatusResponse:
    """
    Simple readiness probe (direct use).

    Example:
        >>> from shared.health import readiness_probe_simple
        >>> @app.get("/readiness")
        >>> async def readiness():
        ...     return await readiness_probe_simple()
    """
    return StatusResponse(status="ready")
