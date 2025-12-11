"""Tests for main application"""

import pytest  # noqa: F401
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_health_check():
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


def test_status():
    """Test status endpoint"""
    response = client.get("/status")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "runner"
    assert data["version"] == "1.0.0"
    assert data["environment"] == "dev"


def test_root():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "runner"


def test_docs_endpoint():
    """Test Swagger UI docs endpoint"""
    response = client.get("/docs")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]


def test_openapi_json():
    """Test OpenAPI JSON endpoint"""
    response = client.get("/openapi.json")
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/json"
    data = response.json()
    assert "openapi" in data
    assert "info" in data
    assert "title" in data["info"]
    assert "version" in data["info"]
    assert data["info"]["version"] != ""


def test_redoc_endpoint():
    """Test ReDoc endpoint"""
    response = client.get("/redoc")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
