"""agsys-common: Common library for agsys backend services."""

__version__ = "0.0.1"

# Convenient imports
from .api_client import ServiceAPIClient, get_service_url
from .health import (
    create_health_endpoint,
    create_liveness_endpoint,
    create_readiness_endpoint,
    health_check_simple,
    liveness_probe_simple,
    readiness_probe_simple,
)
from .logging import configure_logging, get_logger
from .middleware import LoggingMiddleware, logging_middleware
from .models import (
    ErrorResponse,
    GreetingRequest,
    GreetingResponse,
    HealthResponse,
    InterServiceResponse,
    ServiceInfo,
    StatusResponse,
)
from .settings import (
    BaseAWSSettings,
    BaseServiceSettings,
    BaseTracingSettings,
    FullServiceSettings,
)
from .tracing import configure_tracing, get_tracer

__all__ = [
    # API Client
    "ServiceAPIClient",
    "get_service_url",
    # Health
    "create_health_endpoint",
    "create_liveness_endpoint",
    "create_readiness_endpoint",
    "health_check_simple",
    "liveness_probe_simple",
    "readiness_probe_simple",
    # Logging
    "configure_logging",
    "get_logger",
    # Middleware
    "LoggingMiddleware",
    "logging_middleware",
    # Models
    "ErrorResponse",
    "GreetingRequest",
    "GreetingResponse",
    "HealthResponse",
    "InterServiceResponse",
    "ServiceInfo",
    "StatusResponse",
    # Settings
    "BaseAWSSettings",
    "BaseServiceSettings",
    "BaseTracingSettings",
    "FullServiceSettings",
    # Tracing
    "configure_tracing",
    "get_tracer",
]
