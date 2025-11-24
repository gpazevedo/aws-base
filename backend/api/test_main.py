"""Tests for FastAPI application."""

import pytest
from fastapi.testclient import TestClient

from main import app

# Create test client
client = TestClient(app)


# =============================================================================
# Health Check Tests
# =============================================================================


def test_health_check() -> None:
    """Test health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data
    assert "uptime_seconds" in data
    assert data["version"] == "0.1.0"


def test_liveness_probe() -> None:
    """Test liveness probe endpoint."""
    response = client.get("/liveness")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"


def test_readiness_probe() -> None:
    """Test readiness probe endpoint."""
    response = client.get("/readiness")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"


# =============================================================================
# API Endpoint Tests
# =============================================================================


def test_root_endpoint() -> None:
    """Test root endpoint."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, World!"
    assert data["version"] == "0.1.0"


def test_greet_get_default() -> None:
    """Test greet endpoint with default name."""
    response = client.get("/greet")
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, World!"
    assert data["version"] == "0.1.0"


def test_greet_get_with_name() -> None:
    """Test greet endpoint with custom name."""
    response = client.get("/greet?name=Alice")
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, Alice!"
    assert data["version"] == "0.1.0"


def test_greet_post() -> None:
    """Test greet POST endpoint."""
    response = client.post("/greet", json={"name": "Bob"})
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, Bob!"
    assert data["version"] == "0.1.0"


def test_greet_post_validation_error() -> None:
    """Test greet POST endpoint with invalid data."""
    response = client.post("/greet", json={})
    assert response.status_code == 422  # Validation error


def test_error_endpoint() -> None:
    """Test error endpoint returns 500."""
    response = client.get("/error")
    assert response.status_code == 500
    data = response.json()
    assert "detail" in data


# =============================================================================
# Service Integration Tests
# =============================================================================


def test_inter_service_endpoint_missing_url() -> None:
    """
    Test the inter-service endpoint returns validation error when URL is missing.
    """
    response = client.get("/inter-service")
    # Should return 422 validation error when service_url parameter is missing
    assert response.status_code == 422


def test_inter_service_endpoint_with_invalid_url() -> None:
    """
    Test the inter-service endpoint with an invalid URL.

    This should return 503 because the service cannot be reached.
    """
    response = client.get("/inter-service?service_url=http://invalid-url-that-does-not-exist.local/health")
    # The endpoint should be accessible but return 503 (service unavailable)
    assert response.status_code == 503
    data = response.json()
    assert "detail" in data
    assert "Failed to reach service" in data["detail"]


# =============================================================================
# Documentation Tests
# =============================================================================


def test_openapi_schema() -> None:
    """Test OpenAPI schema is accessible."""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    data = response.json()
    assert "openapi" in data
    assert "info" in data
    assert data["info"]["title"] == "AWS Base Python API"


def test_swagger_ui() -> None:
    """Test Swagger UI is accessible."""
    response = client.get("/docs")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]


def test_redoc() -> None:
    """Test ReDoc is accessible."""
    response = client.get("/redoc")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]


# =============================================================================
# Error Handling Tests
# =============================================================================


def test_404_not_found() -> None:
    """Test custom 404 handler."""
    response = client.get("/nonexistent")
    assert response.status_code == 404
    data = response.json()
    assert "error" in data
    assert "available_endpoints" in data
    assert "/" in data["available_endpoints"]
    assert "/inter-service" in data["available_endpoints"]
