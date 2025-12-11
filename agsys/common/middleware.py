"""Shared FastAPI middleware."""

import time
from collections.abc import Callable

import structlog
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

logger = structlog.get_logger(__name__)


class LoggingMiddleware(BaseHTTPMiddleware):
    """
    Middleware for logging HTTP requests and responses.

    Logs request start, completion with duration and status code.
    Adds request context to structlog for correlation.

    Example:
        >>> from shared.middleware import LoggingMiddleware
        >>> app.add_middleware(LoggingMiddleware)
    """

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Process request with logging."""
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


async def logging_middleware(request: Request, call_next: Callable) -> Response:
    """
    Function-based logging middleware (alternative to class-based).

    Use this with @app.middleware("http") decorator.

    Example:
        >>> from shared.middleware import logging_middleware
        >>> @app.middleware("http")
        >>> async def log_requests(request: Request, call_next):
        >>>     return await logging_middleware(request, call_next)
    """
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
