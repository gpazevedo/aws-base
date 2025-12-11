#!/bin/bash
# =============================================================================
# Create New App Runner Service with Shared Library
# =============================================================================
# This script creates a complete App Runner service from scratch with:
# - Backend service directory structure
# - uv Python project setup
# - Shared library integration
# - FastAPI application with App Runner configuration (port 8080)
# - Service-specific Dockerfile for App Runner
# - Terraform configuration
# - OpenTelemetry/ADOT integration
#
# Usage: ./scripts/create-apprunner-service.sh SERVICE_NAME [DESCRIPTION]
#
# Examples:
#   ./scripts/create-apprunner-service.sh web "Web frontend service"
#   ./scripts/create-apprunner-service.sh admin "Admin dashboard service"
#   ./scripts/create-apprunner-service.sh portal
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
  echo "  $0 web \"Web frontend service\""
  echo "  $0 admin \"Admin dashboard service\""
  echo "  $0 portal"
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

echo "🚀 Creating new App Runner service: $SERVICE_NAME"
echo ""
echo "📋 Configuration:"
echo "   Service Name: $SERVICE_NAME"
echo "   Description: $SERVICE_DESCRIPTION"
echo "   Directory: $SERVICE_DIR"
echo "   Type: App Runner (port 8080)"
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
uv add "fastapi[standard]" "uvicorn[standard]" boto3 pydantic pydantic-settings httpx structlog python-dotenv

# Add OpenTelemetry dependencies
echo "📦 Adding OpenTelemetry dependencies..."
uv add opentelemetry-api opentelemetry-sdk opentelemetry-instrumentation-fastapi opentelemetry-instrumentation-httpx opentelemetry-exporter-otlp-proto-grpc

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

import httpx
from fastapi import FastAPI, HTTPException, Query

from common import (
    configure_logging,
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
PROJECT_NAME = os.getenv("PROJECT_NAME", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# App Runner port (must be 8080)
PORT = int(os.getenv("PORT", "8080"))

# =============================================================================
# Logging Setup
# =============================================================================

configure_logging(log_level=LOG_LEVEL)

# Get logger with service context
logger = get_logger(__name__).bind(
    service=SERVICE_NAME,
    environment=ENVIRONMENT,
)

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
        port=PORT,
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
)

# Add middleware
app.add_middleware(LoggingMiddleware)


# =============================================================================
# Health Check Endpoints
# =============================================================================


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Simple health check endpoint"""
    return await health_check_simple(SERVICE_NAME, SERVICE_VERSION, START_TIME)


@app.get("/status", response_model=ServiceInfo)
async def status():
    """Detailed service status"""
    return ServiceInfo(
        name=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
        description="DESCRIPTION_PLACEHOLDER",
    )


# =============================================================================
# Business Logic Endpoints
# =============================================================================


@app.get("/")
async def root():
    """Root endpoint"""
    logger.info("root_endpoint_called")
    return {
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "message": f"Welcome to {SERVICE_NAME} service",
    }


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
# Development Server
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    logger.info("starting_dev_server", port=PORT)
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=PORT,
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

# API Gateway (set by Terraform if integrated)
API_GATEWAY_URL=

# Project Configuration (set by Terraform)
PROJECT_NAME=

# App Runner Configuration
PORT=8080

# Observability (ADOT configuration via Terraform)
# The following are configured automatically by Terraform in App Runner:
# OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
# OTEL_SERVICE_NAME=$SERVICE_NAME
# OTEL_PROPAGATORS=xray
# OTEL_PYTHON_ID_GENERATOR=xray
# OTEL_METRICS_EXPORTER=none
# OTEL_RESOURCE_ATTRIBUTES=service.name=$SERVICE_NAME
# OTEL_PYTHON_DISABLED_INSTRUMENTATIONS=urllib3

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

# Run development server (port 8080)
uv run python main.py

# Visit http://localhost:8080
# API docs: http://localhost:8080/docs
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
- \`API_GATEWAY_URL\` - API Gateway URL (set by Terraform, if integrated)
- \`AWS_REGION\` - AWS region
- \`PORT\` - App Runner port (must be 8080)

## Deployment

\`\`\`bash
# Build and push Docker image
# The script automatically handles CodeArtifact authentication
./scripts/docker-push.sh dev $SERVICE_NAME Dockerfile.apprunner

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
from common import ServiceAPIClient, get_service_url

async with ServiceAPIClient(service_name="$SERVICE_NAME") as client:
    url = get_service_url("other-service")
    response = await client.get(f"{url}/endpoint")
\`\`\`

See [docs/API-KEYS-QUICKSTART.md](../../docs/API-KEYS-QUICKSTART.md) for API key setup.

## App Runner Specifics

- **Port**: Must listen on port 8080 (App Runner requirement)
- **Health Check**: App Runner uses \`/health\` endpoint by default
- **Tracing**: ADOT is installed in the container, App Runner provides OTLP collector on localhost:4317
- **Scaling**: Configured via Terraform (min/max instances, concurrency)

## Architecture

- **Runtime**: Python 3.14 on App Runner
- **Web Framework**: FastAPI with uvicorn
- **Observability**: OpenTelemetry + AWS X-Ray via ADOT
- **Logging**: Structured JSON logging with structlog
- **Deployment**: Docker container on AWS App Runner
EOF

echo "✅ Application files created"
echo ""

# =============================================================================
# Create Dockerfile for App Runner
# =============================================================================

echo "🐳 Creating Dockerfile.apprunner..."

cat > Dockerfile.apprunner <<'EOF'
# =============================================================================
# App Runner Dockerfile for SERVICE_NAME_PLACEHOLDER Service
# =============================================================================
# This Dockerfile builds an App Runner container image using Python 3.14
# App Runner expects the application to listen on port 8080
#
# Multi-architecture support:
# - amd64 (default): For production AWS App Runner (x86_64)
# - arm64: For local testing on ARM machines
#
# Build examples:
#   docker build --platform=linux/amd64 -t SERVICE_NAME_PLACEHOLDER:latest .
#   docker build --platform=linux/arm64 -t SERVICE_NAME_PLACEHOLDER:latest .
# =============================================================================

# Multi-arch support - TARGETPLATFORM is automatically set by Docker BuildKit
# When using --platform=linux/amd64, TARGETPLATFORM=linux/amd64
# When using --platform=linux/arm64, TARGETPLATFORM=linux/arm64
# The python:3.14-slim multi-arch manifest will pull the correct variant
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM python:3.14-slim

# Install uv - fast Python package installer
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR /app

# Set environment variables for uv
ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1

# Copy service files
COPY backend/SERVICE_NAME_PLACEHOLDER/pyproject.toml backend/SERVICE_NAME_PLACEHOLDER/uv.lock* ./

# CodeArtifact authentication (passed at build time)
ARG CODEARTIFACT_INDEX_URL
ARG UV_EXTRA_INDEX_URL=https://pypi.org/simple/
ENV UV_INDEX_URL=${CODEARTIFACT_INDEX_URL}
ENV UV_EXTRA_INDEX_URL=${UV_EXTRA_INDEX_URL}

# Install dependencies to system Python using uv pip
# Export dependencies from lock file and install to system site-packages
RUN uv export --no-dev --frozen > requirements.txt && \
    uv pip install --system --no-cache -r requirements.txt

# Install OpenTelemetry ADOT dependencies for automatic instrumentation
# ADOT provides automatic tracing for FastAPI, boto3, httpx, and more
# See: https://aws-otel.github.io/docs/getting-started/python-sdk
RUN uv pip install --no-cache \
    "opentelemetry-distro[otlp]>=0.24b0" \
    "opentelemetry-sdk-extension-aws~=2.0" \
    "opentelemetry-propagator-aws-xray~=1.0"

# Run ADOT bootstrap to install automatic instrumentation packages
# This detects installed libraries and installs appropriate instrumentors
RUN opentelemetry-bootstrap --action=install

# Copy application code (all .py files except tests)
COPY backend/SERVICE_NAME_PLACEHOLDER/*.py ./

# Remove test files
RUN rm -f test_*.py

# App Runner expects port 8080
EXPOSE 8080

# Health check endpoint (optional but recommended)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Run application with OpenTelemetry automatic instrumentation
# The opentelemetry-instrument wrapper enables automatic tracing
# ADOT environment variables are configured via Terraform
CMD ["opentelemetry-instrument", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

sed -i "s/SERVICE_NAME_PLACEHOLDER/$SERVICE_NAME/g" Dockerfile.apprunner

echo "✅ Dockerfile.apprunner created"
echo ""

# =============================================================================
# Run Terraform Setup Script
# =============================================================================

cd ../..  # Return to project root

if [ -f "$SCRIPTS_DIR/setup-terraform-apprunner.sh" ]; then
  echo "🏗️  Setting up Terraform configuration..."
  echo ""

  read -p "Do you want to set up Terraform configuration for this service? (Y/n): " -n 1 -r
  echo

  if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    bash "$SCRIPTS_DIR/setup-terraform-apprunner.sh" "$SERVICE_NAME"
    echo ""
  else
    echo "⏭️  Skipping Terraform setup"
    echo "   You can run it later with: ./scripts/setup-terraform-apprunner.sh $SERVICE_NAME"
    echo ""
  fi
else
  echo "⚠️  Terraform setup script not found at: $SCRIPTS_DIR/setup-terraform-apprunner.sh"
  echo "   You'll need to set up Terraform manually"
  echo ""
fi

# =============================================================================
# Summary
# =============================================================================

echo "✅ App Runner service '$SERVICE_NAME' created successfully!"
echo ""
echo "📂 Created files:"
echo "   $SERVICE_DIR/main.py"
echo "   $SERVICE_DIR/pyproject.toml"
echo "   $SERVICE_DIR/.env.example"
echo "   $SERVICE_DIR/.gitignore"
echo "   $SERVICE_DIR/Dockerfile.apprunner"
echo "   $SERVICE_DIR/README.md"
echo "   $SERVICE_DIR/tests/test_main.py"
echo "   $SERVICE_DIR/pytest.ini"
echo ""
echo "📦 Dependencies installed:"
echo "   ✅ agsys-common>=0.0.1,<1.0.0 (from CodeArtifact)"
echo "   ✅ fastapi[standard], uvicorn[standard]"
echo "   ✅ boto3, pydantic, httpx, structlog"
echo "   ✅ OpenTelemetry packages"
echo "   ✅ pytest (dev)"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Start development server:"
echo "   cd $SERVICE_DIR"
echo "   uv run python main.py"
echo "   # Visit http://localhost:8080"
echo ""
echo "2. Run tests:"
echo "   cd $SERVICE_DIR"
echo "   uv run pytest"
echo ""
echo "3. Build and deploy:"
echo "   ./scripts/docker-push.sh dev $SERVICE_NAME Dockerfile.apprunner"
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
echo "⚡ App Runner Specifics:"
echo "   - Port 8080 is mandatory for App Runner"
echo "   - ADOT tracing is automatically configured via Terraform"
echo "   - Health checks use /health endpoint"
echo "   - Scaling and resources configured in Terraform"
echo ""
echo "🎉 Happy coding!"
echo ""
