"""Shared OpenTelemetry tracing configuration."""

import os

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from .logging import get_logger

logger = get_logger(__name__)


def configure_tracing(
    service_name: str,
    service_version: str,
    environment: str,
    otlp_endpoint: str = "http://localhost:4317",
    enable_tracing: bool = True,
    app: FastAPI | None = None,
) -> None:
    """
    Configure OpenTelemetry tracing with ADOT.

    Args:
        service_name: Name of the service
        service_version: Version of the service
        environment: Environment (dev, test, prod)
        otlp_endpoint: OTLP collector endpoint
        enable_tracing: Whether to enable tracing
        app: Optional FastAPI app to instrument

    Example:
        >>> from shared.tracing import configure_tracing
        >>> configure_tracing(
        ...     service_name="api",
        ...     service_version="1.0.0",
        ...     environment="dev",
        ...     app=app
        ... )
    """
    logger.info(
        "tracing_configuration_starting",
        enable_tracing=enable_tracing,
        is_test=bool(os.getenv("PYTEST_CURRENT_TEST")),
        is_lambda=bool(os.getenv("AWS_LAMBDA_FUNCTION_NAME")),
        app_provided=app is not None,
    )

    # Disable tracing during tests
    if os.getenv("PYTEST_CURRENT_TEST"):
        logger.info("tracing_disabled", reason="test_environment")
        return

    # Disable application-level tracing in Lambda - use ADOT Lambda Layer instead
    if os.getenv("AWS_LAMBDA_FUNCTION_NAME"):
        logger.info(
            "tracing_disabled",
            reason="lambda_environment",
            message="Use ADOT Lambda Layer for tracing instead of application instrumentation",
        )
        return

    if not enable_tracing:
        logger.info("tracing_disabled", reason="disabled_by_configuration")
        return

    logger.info("initializing_otel_components")

    # Create resource with service information
    resource = Resource.create(
        {
            "service.name": f"{service_name}-{environment}",
            "service.version": service_version,
            "deployment.environment": environment,
        }
    )
    logger.info("otel_resource_created")

    # Configure OTLP exporter to send traces to ADOT collector
    otlp_exporter = OTLPSpanExporter(
        endpoint=otlp_endpoint,
        insecure=True,  # Use insecure for local ADOT collector
    )
    logger.info("otlp_exporter_created", endpoint=otlp_endpoint)

    # Set up tracer provider with batch span processor
    provider = TracerProvider(resource=resource)
    processor = BatchSpanProcessor(otlp_exporter)
    provider.add_span_processor(processor)
    trace.set_tracer_provider(provider)
    logger.info("tracer_provider_configured")

    # Instrument HTTPX client for automatic tracing
    HTTPXClientInstrumentor().instrument()
    logger.info("httpx_instrumented")

    # Instrument FastAPI app if provided
    if app is not None:
        FastAPIInstrumentor.instrument_app(app)
        logger.info("fastapi_instrumented")

    logger.info(
        "tracing_configured",
        service=f"{service_name}-{environment}",
        otlp_endpoint=otlp_endpoint,
    )


def get_tracer(name: str) -> trace.Tracer:
    """
    Get a tracer instance.

    Args:
        name: Tracer name (typically module name)

    Returns:
        OpenTelemetry tracer

    Example:
        >>> from shared.tracing import get_tracer
        >>> tracer = get_tracer(__name__)
        >>> with tracer.start_as_current_span("process_request"):
        ...     # Your code here
        ...     pass
    """
    return trace.get_tracer(name)
