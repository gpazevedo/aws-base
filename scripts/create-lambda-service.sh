#!/bin/bash
# =============================================================================
# Create New Lambda Service with Shared Library
# =============================================================================
# This script creates a complete Lambda service from scratch with:
# - Backend service directory structure
# - uv Python project setup
# - Shared library integration
# - Basic FastAPI application
# - Dockerfile for Lambda
# - Terraform configuration
#
# Usage: ./scripts/create-lambda-service.sh SERVICE_NAME [DESCRIPTION]
#
# Examples:
#   ./scripts/create-lambda-service.sh payments "Payment processing service"
#   ./scripts/create-lambda-service.sh notifications
# =============================================================================

set -e

# =============================================================================
# Parse Arguments
# =============================================================================

SERVICE_NAME="${1}"
SERVICE_DESCRIPTION="${2:-${SERVICE_NAME} service}"

if [ -z "$SERVICE_NAME" ]; then
  echo "❌ Error: Service name is required"
  echo ""
  echo "Usage: $0 SERVICE_NAME [DESCRIPTION]"
  echo ""
  echo "Examples:"
  echo "  $0 payments \"Payment processing service\""
  echo "  $0 notifications"
  echo ""
  exit 1
fi

# Validate service name (alphanumeric, lowercase, hyphens/underscores)
if ! [[ "$SERVICE_NAME" =~ ^[a-z0-9_-]+$ ]]; then
  echo "❌ Error: Service name must be lowercase alphanumeric with hyphens or underscores"
  echo "   Got: $SERVICE_NAME"
  exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

BACKEND_DIR="backend"
SERVICE_DIR="$BACKEND_DIR/$SERVICE_NAME"
SCRIPTS_DIR="scripts"

echo "🚀 Creating new Lambda service: $SERVICE_NAME"
echo ""
echo "📋 Configuration:"
echo "   Service Name: $SERVICE_NAME"
echo "   Description: $SERVICE_DESCRIPTION"
echo "   Directory: $SERVICE_DIR"
echo ""

# =============================================================================
# Check Prerequisites
# =============================================================================

echo "🔍 Checking prerequisites..."

# Check if service already exists
if [ -d "$SERVICE_DIR" ]; then
  echo "❌ Error: Service directory already exists: $SERVICE_DIR"
  exit 1
fi

# Check if uv is installed
if ! command -v uv &> /dev/null; then
  echo "❌ Error: uv is not installed"
  echo "   Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi

echo "✅ Prerequisites checked"
echo ""

# =============================================================================
# Create Service Directory Structure
# =============================================================================

echo "📁 Creating service directory structure..."

mkdir -p "$SERVICE_DIR"
cd "$SERVICE_DIR"

# Initialize uv project
echo "📦 Initializing uv project..."
uv init --no-workspace --name "$SERVICE_NAME"

# Add agsys-common library from CodeArtifact
echo "📚 Adding agsys-common library from CodeArtifact..."

# Check if CodeArtifact is configured
if [ -z "${UV_INDEX_URL:-}" ]; then
    echo "⚠️  CodeArtifact not configured. Configuring now..."
    cd ../..  # Return to project root
    if [ -f "./scripts/configure-codeartifact.sh" ]; then
        # Source the script to set UV_INDEX_URL and UV_EXTRA_INDEX_URL
        eval "$(./scripts/configure-codeartifact.sh)"
    else
        echo "❌ Error: CodeArtifact configuration script not found"
        echo "   Please run: ./scripts/configure-codeartifact.sh"
        exit 1
    fi
    cd "$SERVICE_DIR"  # Return to service directory
fi

# Add agsys-common from CodeArtifact with version constraint
# Note: We manually edit pyproject.toml to avoid uv creating a lock file with stale hash
echo "📚 Adding agsys-common to pyproject.toml..."

# Replace empty dependencies = [] with dependencies containing agsys-common
sed -i 's/^dependencies = \[\]$/dependencies = [\n    "agsys-common>=0.0.1,<1.0.0",\n]/' pyproject.toml

# Clear uv cache for agsys-common to force fresh download
echo "🔄 Clearing uv cache for agsys-common..."
uv cache clean agsys-common || true

# Generate lock file with correct hash from CodeArtifact
echo "🔄 Generating lock file with correct hash..."
uv lock

# Now sync/install with the corrected lock file
echo "📦 Installing dependencies..."
uv sync

# Add common dependencies
echo "📦 Adding dependencies..."
uv add "fastapi[standard]" "uvicorn[standard]" boto3 pydantic pydantic-settings httpx "mangum>=0.19.0"

# Add development dependencies
echo "🔧 Adding dev dependencies..."
uv add --dev pytest pytest-asyncio pytest-cov httpx

echo "✅ Dependencies installed"
echo ""

# =============================================================================
# Create Application Files
# =============================================================================

echo "📝 Creating application files..."

# Create main.py
cat > main.py <<'EOF'
"""
SERVICE_NAME_PLACEHOLDER Service

DESCRIPTION_PLACEHOLDER
"""

import os
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse

from common import (
    configure_logging,
    configure_tracing,
    get_logger,
    LoggingMiddleware,
    health_check_simple,
    HealthResponse,
    ServiceInfo,
    InterServiceResponse,
)

# =============================================================================
# Configuration
# =============================================================================

SERVICE_NAME = "SERVICE_NAME_PLACEHOLDER"
SERVICE_VERSION = "1.0.0"
START_TIME = time.time()  # Unix timestamp for uptime calculation

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# =============================================================================
# Logging and Tracing Setup
# =============================================================================

configure_logging(log_level=LOG_LEVEL)

# Get logger with service context
logger = get_logger(__name__).bind(
    service=SERVICE_NAME,
    environment=ENVIRONMENT,
)

# Note: Tracing is automatically configured via ADOT Lambda Layer
# The ADOT layer provides automatic instrumentation for:
# - AWS SDK calls (boto3)
# - HTTP requests (httpx, requests)
# - Database calls
# - FastAPI endpoints
# No manual configure_tracing() needed when using ADOT layer
logger.info("service_initialized", adot_layer="enabled")


# =============================================================================
# Application Lifecycle
# =============================================================================


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Manage application lifespan with proper resource cleanup.

    This modern FastAPI pattern replaces the deprecated @app.on_event decorators.
    Resources are initialized on startup and cleaned up on shutdown.
    """
    logger.info(
        "service_starting",
        service=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
    )

    # Initialize shared HTTP client for inter-service communication
    app.state.http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(30.0),
        limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
    )

    yield

    # Cleanup
    logger.info("service_stopping", service=SERVICE_NAME)
    await app.state.http_client.aclose()


# =============================================================================
# FastAPI Application
# =============================================================================

app = FastAPI(
    title=f"{SERVICE_NAME} Service",
    description="DESCRIPTION_PLACEHOLDER",
    version=SERVICE_VERSION,
    lifespan=lifespan,
    root_path=f"/{SERVICE_NAME}",  # API Gateway path prefix - helps with OpenAPI docs
)

# Add middleware
app.add_middleware(LoggingMiddleware)


# =============================================================================
# Routing Strategy
# =============================================================================
# For services deployed with API Gateway path prefix (e.g., /api3/*):
# - API Gateway sends full path including prefix to Lambda
# - We need to handle both root paths and prefixed paths
# - Use FastAPI router to handle the prefix

# Create router for service endpoints
router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """Simple health check endpoint"""
    return await health_check_simple(SERVICE_NAME, SERVICE_VERSION, START_TIME)


@router.get("/status", response_model=ServiceInfo)
async def status():
    """Detailed service status"""
    return ServiceInfo(
        name=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
        description="DESCRIPTION_PLACEHOLDER",
    )


@router.get("/")
async def root():
    """Root endpoint"""
    logger.info("root_endpoint_called")
    return {
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "message": f"Welcome to {SERVICE_NAME} service",
    }


# Mount router at both root and service prefix to handle API Gateway routing
# This allows the service to work whether accessed at "/" or "/SERVICE_NAME/"
app.include_router(router)  # For root-level access
app.include_router(router, prefix=f"/{SERVICE_NAME}")  # For prefixed access


# =============================================================================
# Inter-Service Communication Endpoints
# =============================================================================


@app.get("/inter-service", response_model=InterServiceResponse, tags=["Service Integration"])
async def call_service(
    service_url: str = Query(
        ...,
        description="Full URL of the service endpoint to call (e.g., https://example.com/health)",
    ),
) -> InterServiceResponse:
    """
    Call another service's endpoint and return the response.

    This endpoint demonstrates service-to-service communication by calling
    any provided service URL and returning what it received.
    Uses the shared HTTP client from app.state for connection pooling.

    Args:
        service_url: Full URL of the service endpoint to call (query parameter)

    Returns:
        InterServiceResponse: The response from the target service including
                             status code, response time, and the full response body

    Raises:
        HTTPException: If the target service is unreachable or returns an error

    Example:
        GET /inter-service?service_url=https://example.com/health
    """
    start_time = time.time()

    logger.info("calling_external_service", target_url=service_url)

    try:
        # Use shared HTTP client from app.state (initialized in lifespan)
        response = await app.state.http_client.get(service_url)
        response_time = (time.time() - start_time) * 1000  # Convert to ms

        logger.info(
            "external_service_response",
            target_url=service_url,
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
        )

        # Return the response regardless of status code
        return InterServiceResponse(
            service_response=response.json(),
            status_code=response.status_code,
            response_time_ms=round(response_time, 2),
            target_url=service_url,
        )
    except httpx.RequestError as e:
        logger.error(
            "external_service_request_error",
            target_url=service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=503,
            detail=f"Failed to reach service at {service_url}: {str(e)}",
        ) from e
    except Exception as e:
        logger.exception(
            "external_service_unexpected_error",
            target_url=service_url,
            error=str(e),
        )
        raise HTTPException(
            status_code=500,
            detail=f"Unexpected error calling service at {service_url}: {str(e)}",
        ) from e


# Add your business logic endpoints here
# Example:
# @app.post("/process")
# async def process_data(data: YourModel):
#     logger.info("processing_data", data=data.dict())
#     # Your business logic here
#     return {"status": "processed"}


# =============================================================================
# Lambda Handler
# =============================================================================

# Mangum adapter to run FastAPI on AWS Lambda
# Python 3.14 compatibility: Explicitly manage event loop for Lambda

try:
    import asyncio
    from mangum import Mangum

    def handler(event, context):
        """
        AWS Lambda handler with Python 3.14 asyncio compatibility.

        Python 3.14 removed the implicit event loop from asyncio.get_event_loop().
        We need to explicitly create and set an event loop for Mangum to work.

        Performance optimization: HTTP client is reused across warm Lambda invocations
        when the event loop is the same. If the loop changes, the client is recreated
        to avoid "bound to a different event loop" errors.
        """
        # Get or create event loop - reuse existing loop from warm container if available
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            # No running loop - create and set a new one
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

        # Store the loop ID to detect when Lambda creates a new loop
        current_loop_id = id(asyncio.get_event_loop())

        # Initialize or recreate HTTP client if loop changed
        if (
            not hasattr(app.state, "http_client")
            or not hasattr(app.state, "_loop_id")
            or app.state._loop_id != current_loop_id
        ):
            # Clean up old client if it exists
            if hasattr(app.state, "http_client"):
                try:
                    # Close old client (async operation, so run in the current loop)
                    asyncio.get_event_loop().run_until_complete(app.state.http_client.aclose())
                except Exception:
                    pass  # Ignore errors from closing stale client

            # Create new HTTP client bound to current event loop
            app.state.http_client = httpx.AsyncClient(
                timeout=httpx.Timeout(30.0),
                limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
            )
            app.state._loop_id = current_loop_id

        # Create Mangum handler with the app (lifespan="off" to avoid double initialization)
        mangum_handler = Mangum(app, lifespan="off")
        return mangum_handler(event, context)

        # Note: Event loop and HTTP client are NOT closed here
        # They will be reused across Lambda invocations when the loop stays the same
        # Lambda runtime will clean them up when the container is terminated

    logger.info("lambda_handler_configured")
except ImportError:
    logger.warning("mangum_not_installed", msg="Lambda handler not available")
    handler = None


# =============================================================================
# Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    logger.info("starting_dev_server", port=8000)
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_config=None,  # Use our custom logging
    )
EOF

# Replace placeholders
sed -i "s/SERVICE_NAME_PLACEHOLDER/$SERVICE_NAME/g" main.py
sed -i "s/DESCRIPTION_PLACEHOLDER/$SERVICE_DESCRIPTION/g" main.py

# Create .env.example
cat > .env.example <<EOF
# Service Configuration
SERVICE_NAME=$SERVICE_NAME
ENVIRONMENT=dev
LOG_LEVEL=DEBUG

# AWS Configuration
AWS_REGION=us-east-1

# API Gateway (set by Terraform)
API_GATEWAY_URL=

# Project Configuration (set by Terraform)
PROJECT_NAME=

# Observability (configured via Terraform)
# ADOT Layer provides automatic instrumentation for tracing
# AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument
# OTEL_SERVICE_NAME=$SERVICE_NAME
# OTEL_TRACES_SAMPLER=xray
# OTEL_PROPAGATORS=xray

# Add your service-specific environment variables here
EOF

# Create .gitignore
cat > .gitignore <<'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
*.egg-info/
dist/
build/

# uv
.venv/
uv.lock

# Environment
.env
.env.local

# IDE
.vscode/
.idea/
*.swp
*.swo

# Testing
.pytest_cache/
.coverage
htmlcov/

# Logs
*.log
EOF

# Create tests directory
mkdir -p tests
cat > tests/__init__.py <<'EOF'
"""Tests for SERVICE_NAME_PLACEHOLDER service"""
EOF

sed -i "s/SERVICE_NAME_PLACEHOLDER/$SERVICE_NAME/g" tests/__init__.py

cat > tests/test_main.py <<'EOF'
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
    assert data["name"] == "SERVICE_NAME_PLACEHOLDER"
    assert data["version"] == "1.0.0"
    assert data["environment"] == "dev"


def test_root():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "SERVICE_NAME_PLACEHOLDER"


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
EOF

sed -i "s/SERVICE_NAME_PLACEHOLDER/$SERVICE_NAME/g" tests/test_main.py

# Create pytest.ini
cat > pytest.ini <<'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
addopts = -v --strict-markers --cov=. --cov-report=term-missing
EOF

# Create README.md
cat > README.md <<EOF
# $SERVICE_NAME Service

$SERVICE_DESCRIPTION

## Quick Start

### Development

\`\`\`bash
# Install dependencies
uv sync

# Run development server
uv run python main.py

# Visit http://localhost:8000
# API docs: http://localhost:8000/docs
\`\`\`

### Testing

\`\`\`bash
# Run tests
uv run pytest

# Run with coverage
uv run pytest --cov
\`\`\`

## API Endpoints

- \`GET /health\` - Health check
- \`GET /status\` - Service status
- \`GET /\` - Root endpoint

## Environment Variables

See \`.env.example\` for all available environment variables.

Required:
- \`SERVICE_NAME\` - Service identifier
- \`ENVIRONMENT\` - Environment (dev, test, prod)
- \`PROJECT_NAME\` - Project name (set by Terraform)
- \`API_GATEWAY_URL\` - API Gateway URL (set by Terraform)

## Deployment

\`\`\`bash
# Build and push Docker image
# The script automatically handles CodeArtifact authentication
./scripts/docker-push.sh dev $SERVICE_NAME Dockerfile.lambda

# Deploy infrastructure
make app-init-dev app-apply-dev
\`\`\`

**Note:** The build script automatically detects and configures CodeArtifact authentication when needed.

## Using agsys-common Library

This service uses the agsys-common library from CodeArtifact for:
- ✅ Structured logging (\`configure_logging\`, \`get_logger\`)
- ✅ OpenTelemetry tracing (\`configure_tracing\`)
- ✅ Request logging middleware (\`LoggingMiddleware\`)
- ✅ Health check utilities (\`health_check_simple\`)
- ✅ Inter-service API calls (\`ServiceAPIClient\`)

The library is installed from AWS CodeArtifact during build.

See [docs/SHARED-LIBRARY.md](../../docs/SHARED-LIBRARY.md) for details.

## Inter-Service Communication

\`\`\`python
from shared import ServiceAPIClient, get_service_url

async with ServiceAPIClient(service_name="$SERVICE_NAME") as client:
    url = get_service_url("other-service")
    response = await client.get(f"{url}/endpoint")
\`\`\`

See [docs/API-KEYS-QUICKSTART.md](../../docs/API-KEYS-QUICKSTART.md) for API key setup.
EOF

echo "✅ Application files created"
echo ""

# =============================================================================
# Create Dockerfile for Lambda
# =============================================================================

echo "🐳 Creating Dockerfile..."

cat > Dockerfile.lambda <<'EOF_DOCKER'
# =============================================================================
# Lambda Container Image for SERVICE_NAME Service
# =============================================================================
# Multi-architecture build for AWS Lambda
# Supports: linux/amd64, linux/arm64
# =============================================================================

# Use AWS Lambda Python base image
FROM public.ecr.aws/lambda/python:3.14

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy service files
COPY backend/SERVICE_NAME/pyproject.toml backend/SERVICE_NAME/uv.lock* ./

# CodeArtifact authentication (passed at build time)
ARG CODEARTIFACT_INDEX_URL
ARG UV_EXTRA_INDEX_URL=https://pypi.org/simple/
ENV UV_INDEX_URL=${CODEARTIFACT_INDEX_URL}
ENV UV_EXTRA_INDEX_URL=${UV_EXTRA_INDEX_URL}

# Install dependencies to system Python using uv pip
# Export dependencies from lock file and install to system site-packages
RUN uv export --no-dev --frozen > requirements.txt && \
    uv pip install --system --no-cache -r requirements.txt

# Copy application code (all .py files except tests)
COPY backend/SERVICE_NAME/*.py ./

# Remove test files
RUN rm -f test_*.py

# Fix permissions for Lambda runtime
# Lambda runs as UID 993, ensure all files are readable
RUN chmod -R a+rX ${LAMBDA_TASK_ROOT}

# Set the Lambda handler
CMD ["main.handler"]
EOF_DOCKER

# Replace SERVICE_NAME placeholder with actual service name
sed -i "s/SERVICE_NAME/$SERVICE_NAME/g" Dockerfile.lambda

echo "✅ Dockerfile created"
echo ""

# =============================================================================
# Run Terraform Setup Script
# =============================================================================

cd ../..  # Return to project root

if [ -f "$SCRIPTS_DIR/setup-terraform-lambda.sh" ]; then
  echo "🏗️  Setting up Terraform configuration..."
  echo ""

  read -p "Do you want to set up Terraform configuration for this service? (Y/n): " -n 1 -r
  echo

  if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    bash "$SCRIPTS_DIR/setup-terraform-lambda.sh" "$SERVICE_NAME"
    echo ""
  else
    echo "⏭️  Skipping Terraform setup"
    echo "   You can run it later with: ./scripts/setup-terraform-lambda.sh $SERVICE_NAME"
    echo ""
  fi
else
  echo "⚠️  Terraform setup script not found at: $SCRIPTS_DIR/setup-terraform-lambda.sh"
  echo "   You'll need to set up Terraform manually"
  echo ""
fi

# =============================================================================
# Summary
# =============================================================================

echo "✅ Lambda service '$SERVICE_NAME' created successfully!"
echo ""
echo "📂 Created files:"
echo "   $SERVICE_DIR/main.py"
echo "   $SERVICE_DIR/pyproject.toml"
echo "   $SERVICE_DIR/.env.example"
echo "   $SERVICE_DIR/.gitignore"
echo "   $SERVICE_DIR/Dockerfile.lambda"
echo "   $SERVICE_DIR/README.md"
echo "   $SERVICE_DIR/tests/test_main.py"
echo "   $SERVICE_DIR/pytest.ini"
echo ""
echo "📦 Dependencies installed:"
echo "   ✅ agsys-common>=0.0.1,<1.0.0 (from CodeArtifact)"
echo "   ✅ fastapi[standard], uvicorn[standard]"
echo "   ✅ boto3, pydantic, httpx"
echo "   ✅ pytest (dev)"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Start development server:"
echo "   cd $SERVICE_DIR"
echo "   uv run python main.py"
echo "   # Visit http://localhost:8000"
echo ""
echo "2. Run tests:"
echo "   cd $SERVICE_DIR"
echo "   uv run pytest"
echo ""
echo "3. Build and deploy:"
echo "   ./scripts/docker-push.sh dev $SERVICE_NAME Dockerfile.lambda"
echo "   make app-init-dev app-apply-dev"
echo ""
echo "4. Customize your service:"
echo "   - Add business logic to $SERVICE_DIR/main.py"
echo "   - Add tests to $SERVICE_DIR/tests/"
echo "   - Update $SERVICE_DIR/README.md"
echo "   - Configure environment in $SERVICE_DIR/.env.example"
echo ""
echo "📖 Documentation:"
echo "   - Shared Library: docs/SHARED-LIBRARY.md"
echo "   - API Keys: docs/API-KEYS-QUICKSTART.md"
echo "   - Adding Services: docs/ADDING-SERVICES.md"
echo ""
echo "🎉 Happy coding!"
echo ""
