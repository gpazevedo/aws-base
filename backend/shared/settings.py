"""Shared settings base classes using Pydantic."""

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class BaseServiceSettings(BaseSettings):
    """
    Base settings class for all services.

    Provides common configuration fields that all services need.
    Extend this class in your service-specific settings.

    Example:
        >>> from shared.settings import BaseServiceSettings
        >>> class MyServiceSettings(BaseServiceSettings):
        ...     my_custom_field: str = "value"
        >>> settings = MyServiceSettings(service_name="my-service")
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # Service identification
    service_name: str = Field(..., description="Service name")
    service_version: str = Field(default="1.0.0", description="Service version")
    environment: str = Field(default="dev", description="Environment (dev, test, prod)")

    # Logging configuration
    log_level: str = Field(default="INFO", description="Logging level")

    # HTTP client settings
    http_timeout: float = Field(default=30.0, description="HTTP timeout in seconds")


class BaseTracingSettings(BaseSettings):
    """
    Base settings for services using OpenTelemetry tracing.

    Example:
        >>> from shared.settings import BaseServiceSettings, BaseTracingSettings
        >>> class MyServiceSettings(BaseServiceSettings, BaseTracingSettings):
        ...     pass
        >>> settings = MyServiceSettings(service_name="my-service")
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Tracing configuration
    enable_tracing: bool = Field(default=True, description="Enable OpenTelemetry tracing")
    otlp_endpoint: str = Field(
        default="http://localhost:4317",
        description="OTLP collector endpoint",
    )


class BaseAWSSettings(BaseSettings):
    """
    Base settings for services using AWS.

    Example:
        >>> from shared.settings import BaseServiceSettings, BaseAWSSettings
        >>> class MyServiceSettings(BaseServiceSettings, BaseAWSSettings):
        ...     pass
        >>> settings = MyServiceSettings(service_name="my-service")
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # AWS configuration
    aws_region: str = Field(default="us-east-1", description="AWS region")


class FullServiceSettings(BaseServiceSettings, BaseTracingSettings, BaseAWSSettings):
    """
    Complete service settings combining all base classes.

    Use this for services that need all common configuration.

    Example:
        >>> from shared.settings import FullServiceSettings
        >>> class MyServiceSettings(FullServiceSettings):
        ...     # Add your service-specific settings
        ...     database_url: str = "postgresql://..."
        >>> settings = MyServiceSettings(service_name="my-service")
    """

    pass
