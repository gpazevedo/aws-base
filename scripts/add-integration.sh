#!/bin/bash
# =============================================================================
# Add Integration Router to Existing Service
# =============================================================================
# This script adds the integration router functionality to an existing service:
# - Creates app/routers/integration.py with inter-service communication endpoint
# - Updates main.py to import and include the integration router
#
# Usage: ./scripts/add-integration.sh ENVIRONMENT SERVICE_NAME
#
# Examples:
#   ./scripts/add-integration.sh dev payments
#   ./scripts/add-integration.sh prod notifications
# =============================================================================

set -e

# =============================================================================
# Parse Arguments
# =============================================================================

ENVIRONMENT="${1}"
SERVICE_NAME="${2}"

if [ -z "$ENVIRONMENT" ] || [ -z "$SERVICE_NAME" ]; then
  echo "❌ Error: Both environment and service name are required"
  echo ""
  echo "Usage: $0 ENVIRONMENT SERVICE_NAME"
  echo ""
  echo "Examples:"
  echo "  $0 dev payments"
  echo "  $0 prod notifications"
  echo ""
  exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

BACKEND_DIR="backend"
SERVICE_DIR="$BACKEND_DIR/$SERVICE_NAME"
MAIN_FILE="$SERVICE_DIR/main.py"
INTEGRATION_FILE="$SERVICE_DIR/app/routers/integration.py"
TEST_FILE="$SERVICE_DIR/tests/test_integration.py"

echo "🚀 Adding integration router to service: $SERVICE_NAME"
echo ""
echo "📋 Configuration:"
echo "   Environment: $ENVIRONMENT"
echo "   Service Name: $SERVICE_NAME"
echo "   Service Directory: $SERVICE_DIR"
echo ""

# =============================================================================
# Check Prerequisites
# =============================================================================

echo "🔍 Checking prerequisites..."

# Check if service directory exists
if [ ! -d "$SERVICE_DIR" ]; then
  echo "❌ Error: Service directory does not exist: $SERVICE_DIR"
  exit 1
fi

# Check if main.py exists
if [ ! -f "$MAIN_FILE" ]; then
  echo "❌ Error: main.py not found at: $MAIN_FILE"
  exit 1
fi

# Check if app/routers directory exists
if [ ! -d "$SERVICE_DIR/app/routers" ]; then
  echo "❌ Error: app/routers directory not found at: $SERVICE_DIR/app/routers"
  exit 1
fi

# Check if integration.py already exists
if [ -f "$INTEGRATION_FILE" ]; then
  echo "⚠️  Warning: integration.py already exists at: $INTEGRATION_FILE"
  read -p "Do you want to overwrite it? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborted by user"
    exit 1
  fi
fi

echo "✅ Prerequisites checked"
echo ""

# =============================================================================
# Create integration.py
# =============================================================================

echo "📝 Creating app/routers/integration.py..."

cat > "$INTEGRATION_FILE" <<'EOF'
import time
from fastapi import APIRouter, Query, HTTPException, Request
from common import InterServiceResponse, get_logger
from app.config import SERVICE_NAME, ENVIRONMENT

router = APIRouter(tags=["Service Integration"])
logger = get_logger(__name__).bind(service=SERVICE_NAME, environment=ENVIRONMENT)

@router.get("/inter-service", response_model=InterServiceResponse)
async def call_service(
    request: Request,
    service_url: str = Query(..., description="Full URL of the service endpoint"),
) -> InterServiceResponse:
    start_time = time.time()
    logger.info("calling_external_service", target_url=service_url)

    if not service_url.startswith("http"):
        logger.error("external_service_invalid_url", target_url=service_url)
        raise HTTPException(status_code=400, detail="Invalid service URL")

    try:
        # Access shared client from app state
        response = await request.app.state.http_client.get(service_url)
        response_time = (time.time() - start_time) * 1000

        return InterServiceResponse(
            service_response=response.json(),
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
            target_url=service_url,
        )
    except Exception as e:
        logger.exception("external_service_unexpected_error", target_url=service_url, error=str(e))
        raise HTTPException(status_code=500, detail=str(e))
EOF

echo "✅ Created integration.py"
echo ""

# =============================================================================
# Update main.py - Add integration import
# =============================================================================

echo "📝 Updating main.py imports..."

# Check if the import line exists and contains "integration"
if grep -q "^from app.routers import" "$MAIN_FILE"; then
  # Check if integration is already imported
  if grep "^from app.routers import" "$MAIN_FILE" | grep -q "integration"; then
    echo "✅ integration already imported in main.py"
  else
    # Add integration to the import line (handles both single and multiple imports)
    # This regex matches the end of the import line and adds integration before the newline
    sed -i 's/^\(from app.routers import.*\)$/\1, integration/' "$MAIN_FILE"
    echo "✅ Added integration to imports"
  fi
else
  echo "⚠️  Warning: Could not find 'from app.routers import' line in main.py"
  echo "   Please manually add: from app.routers import system, integration"
fi

echo ""

# =============================================================================
# Update main.py - Add integration router include
# =============================================================================

echo "📝 Updating main.py router includes..."

# Check if the router include already exists
if grep -q "api_router.include_router(integration.router)" "$MAIN_FILE"; then
  echo "✅ integration.router already included in main.py"
else
  # Find the line with api_router.include_router and add integration after it
  # This will add it after the last include_router line
  if grep -q "^api_router.include_router" "$MAIN_FILE"; then
    # Get the line number of the last api_router.include_router
    LAST_INCLUDE_LINE=$(grep -n "^api_router.include_router" "$MAIN_FILE" | tail -1 | cut -d: -f1)

    # Insert the new line after the last include_router
    sed -i "${LAST_INCLUDE_LINE}a api_router.include_router(integration.router)" "$MAIN_FILE"
    echo "✅ Added api_router.include_router(integration.router)"
  else
    echo "⚠️  Warning: Could not find any 'api_router.include_router' lines in main.py"
    echo "   Please manually add: api_router.include_router(integration.router)"
  fi
fi

echo ""

# =============================================================================
# Create tests/test_embebedings.py
# =============================================================================

echo "📝 Creating tests/test_embebedings.py..."

# Read the template and replace 'vector' with the service name
cat > "$TEST_FILE" <<EOF
"""Tests for Services Integration."""

import os
from app.config import SERVICE_NAME

import pytest

# Set environment variable before importing app to prevent tracing initialization
os.environ["PYTEST_CURRENT_TEST"] = "true"

from fastapi.testclient import TestClient
from main import app


@pytest.fixture(scope="module")
def client():
    """Create test client with lifespan context."""
    with TestClient(app) as test_client:
        yield test_client


# =============================================================================
# Service Integration Tests
# =============================================================================


def test_inter_service_endpoint_missing_url(client) -> None:
    """
    Test the inter-service endpoint returns validation error when URL is missing.
    """
    response = client.get("/inter-service")
    # Should return 422 validation error when service_url parameter is missing
    assert response.status_code == 422


def test_inter_service_endpoint_with_invalid_url(client) -> None:
    """
    Test the inter-service endpoint with an invalid URL.

    This should return 503 because the service cannot be reached.
    """
    invalid = "http://invalid-url-that-does-not-exist.local/health"
    response = client.get(
        "/inter-service?service_url=" + invalid
    )
    # The endpoint should be accessible but return 503 (service unavailable)
    assert response.status_code == 503
    data = response.json()
    assert "detail" in data
    assert "Service unavailable: " + invalid in data["detail"]


def test_inter_service_endpoint_calling_itself(client) -> None:
    """
    Test the inter-service endpoint calling the local health endpoint.

    This test demonstrates working inter-service communication by having the
    service call its own health endpoint. This works locally when the service
    is running on http://localhost:8000.

    Note: This test requires the service to be running locally on port 8000.
    You can start it with: python main.py or uvicorn main:app --host 0.0.0.0 --port 8000
    """
    import httpx

    # First check if the service is running locally
    try:
        httpx.get("http://localhost:8000/health", timeout=2.0)
    except (httpx.ConnectError, httpx.TimeoutException):
        pytest.skip("Service not running on localhost:8000 - start with: python main.py")

    # Now test the inter-service endpoint calling the local health endpoint
    response = client.get("/inter-service?service_url=http://localhost:8000/health")

    # Should successfully call the service
    assert response.status_code == 200
    data = response.json()

    # Verify the response structure
    assert "service_response" in data
    assert "status_code" in data
    assert "response_time_ms" in data
    assert "target_url" in data

    # Verify the service_response contains health check data
    service_response = data["service_response"]
    assert service_response["name"] == SERVICE_NAME
    assert service_response["status"] == "healthy"
    assert "version" in service_response
    assert "uptime_seconds" in service_response

    # Verify metadata
    assert data["status_code"] == 200
    assert data["target_url"] == "http://localhost:8000/health"
    assert data["response_time_ms"] > 0
EOF

echo "✅ Created tests/" + "$TEST_FILE"
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "✅ Integration router added successfully to '$SERVICE_NAME' service!"
echo ""
echo "📂 Modified/Created files:"
echo "   ✅ $INTEGRATION_FILE (created)"
echo "   ✅ $MAIN_FILE (updated)"
echo "   ✅ $TEST_FILE (created)"
echo ""
echo "🔧 Changes made:"
echo "   1. Created integration router with /inter-service endpoint"
echo "   2. Updated imports in main.py to include integration"
echo "   3. Added integration.router to api_router"
echo "   4. Created integration tests"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Test the integration endpoint locally:"
echo "   cd $SERVICE_DIR"
echo "   uv run python main.py"
echo "   # Visit http://localhost:8000/docs"
echo "   # Test the /inter-service endpoint"
echo ""
echo "2. Run tests to ensure nothing broke:"
echo "   cd $SERVICE_DIR"
echo "   uv run pytest"
echo ""
echo "3. Deploy the changes:"
echo "   ./scripts/docker-push.sh $ENVIRONMENT $SERVICE_NAME Dockerfile.lambda"
echo "   make app-apply-$ENVIRONMENT"
echo ""
echo "📖 The /inter-service endpoint allows this service to call other services"
echo "   Example: GET /inter-service?service_url=https://api.example.com/endpoint"
echo ""
echo "🎉 Done!"
echo ""
