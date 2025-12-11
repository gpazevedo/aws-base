"""Shared Pydantic models used across services."""

from pydantic import BaseModel, Field


# =============================================================================
# Health Check Models
# =============================================================================


class HealthResponse(BaseModel):
    """Health check response model."""

    status: str = Field(..., description="Health status (healthy, degraded, unhealthy)")
    timestamp: str = Field(..., description="ISO 8601 timestamp")
    uptime_seconds: float = Field(..., description="Service uptime in seconds")
    name: str = Field(..., description="Service name")
    version: str = Field(..., description="Service version")


class StatusResponse(BaseModel):
    """Simple status response model."""

    status: str = Field(..., description="Status value (alive, ready, etc.)")


# =============================================================================
# Common Request/Response Models
# =============================================================================


class GreetingRequest(BaseModel):
    """Request model for greeting endpoints."""

    name: str = Field(..., description="Name to greet", min_length=1)


class GreetingResponse(BaseModel):
    """Response model for greeting endpoints."""

    message: str = Field(..., description="Greeting message")
    version: str = Field(..., description="Service version")


class ErrorResponse(BaseModel):
    """Error response model."""

    error: str = Field(..., description="Error type or code")
    detail: str | None = Field(None, description="Detailed error message")
    timestamp: str | None = Field(None, description="Error timestamp")


# =============================================================================
# Inter-Service Communication Models
# =============================================================================


class InterServiceResponse(BaseModel):
    """Response from inter-service call."""

    service_response: dict = Field(..., description="Response from target service")
    status_code: int = Field(..., description="HTTP status code")
    response_time_ms: float = Field(..., description="Response time in milliseconds")
    target_url: str = Field(..., description="URL that was called")


# =============================================================================
# Metadata Models
# =============================================================================


class ServiceInfo(BaseModel):
    """Service information model."""

    name: str = Field(..., description="Service name")
    version: str = Field(..., description="Service version")
    environment: str = Field(..., description="Environment (dev, test, prod)")
    description: str | None = Field(None, description="Service description")
