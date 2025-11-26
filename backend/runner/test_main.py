"""Tests for the AppRunner service."""

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient
from main import app, settings


@pytest.fixture
def client():
    """Create a test client."""
    return TestClient(app)


def test_root_endpoint(client):
    """Test the root endpoint."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "version" in data
    assert settings.service_name in data["message"]


def test_health_endpoint(client):
    """Test the health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data
    assert "uptime_seconds" in data
    assert "version" in data
    assert "service_name" in data
    assert data["service_name"] == settings.service_name


def test_liveness_endpoint(client):
    """Test the liveness probe endpoint."""
    response = client.get("/liveness")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"


@pytest.mark.asyncio
async def test_readiness_endpoint_success(client):
    """Test the readiness probe endpoint when API service is reachable."""
    mock_response = AsyncMock()
    mock_response.status_code = 200

    with patch("httpx.AsyncClient") as mock_client:
        mock_client.return_value.__aenter__.return_value.get = AsyncMock(return_value=mock_response)
        response = client.get("/readiness")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ready"


def test_greet_get_endpoint(client):
    """Test the greet endpoint with GET request."""
    response = client.get("/greet?name=Alice")
    assert response.status_code == 200
    data = response.json()
    assert "Alice" in data["message"]
    assert data["version"] == settings.service_version


def test_greet_post_endpoint(client):
    """Test the greet endpoint with POST request."""
    response = client.post("/greet", json={"name": "Bob"})
    assert response.status_code == 200
    data = response.json()
    assert "Bob" in data["message"]
    assert data["version"] == settings.service_version


def test_error_endpoint(client):
    """Test the error endpoint."""
    response = client.get("/error")
    assert response.status_code == 500
    data = response.json()
    assert "detail" in data


def test_not_found_endpoint(client):
    """Test 404 handler."""
    response = client.get("/nonexistent")
    assert response.status_code == 404
    data = response.json()
    assert "error" in data
    assert "available_endpoints" in data


def test_api_health_endpoint_structure(client):
    """
    Test the API health endpoint structure.

    Note: This endpoint requires a running API service to fully test.
    For unit tests, we verify the endpoint exists and returns proper error
    when the API service is not available.
    """
    # Without a running API service, this will return 503
    response = client.get("/api-health")
    # The endpoint should be accessible (not 404)
    assert response.status_code in [200, 503]


def test_openapi_docs(client):
    """Test that OpenAPI documentation is available."""
    response = client.get("/docs")
    assert response.status_code == 200

    response = client.get("/redoc")
    assert response.status_code == 200

    response = client.get("/openapi.json")
    assert response.status_code == 200
    data = response.json()
    assert "openapi" in data
    assert "info" in data
    assert "paths" in data
