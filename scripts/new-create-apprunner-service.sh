#!/bin/bash
# =============================================================================
# Create New App Runner Service with Shared Library
# =============================================================================
# This script creates a complete App Runner service from scratch with:
# - Backend service directory structure
# - uv Python project setup
# - Shared library integration
# - Basic FastAPI application (port 8080)
# - Dockerfile for App Runner
# - Terraform configuration
#
# Usage: ./scripts/new-create-apprunner-service.sh SERVICE_NAME [DESCRIPTION]
#
# Examples:
#   ./scripts/new-create-apprunner-service.sh web "Web frontend service"
#   ./scripts/new-create-apprunner-service.sh portal
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

# Add common dependencies (App Runner uses different packages than Lambda)
echo "📦 Adding dependencies..."
uv add "fastapi[standard]" "uvicorn[standard]" boto3 pydantic pydantic-settings httpx

# Add development dependencies
echo "🔧 Adding dev dependencies..."
uv add --dev pytest pytest-asyncio pytest-cov httpx

echo "✅ Dependencies installed"
echo ""

# =============================================================================
# Create Application Files
# =============================================================================

echo "📝 Creating application files..."

mkdir -p app

# Create app/config.py
cat > app/config.py <<'EOF'
import os
import time

# Service Metadata
SERVICE_NAME = "SERVICE_NAME_PLACEHOLDER"
SERVICE_DESCRIPTION = "DESCRIPTION_PLACEHOLDER"
SERVICE_VERSION = "0.0.1"
START_TIME = time.time()

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# App Runner Configuration
# App Runner REQUIRES port 8080
PORT = int(os.getenv("PORT", "8080"))

EOF

# Replace placeholders
sed -i "s/SERVICE_NAME_PLACEHOLDER/$SERVICE_NAME/g" app/config.py
sed -i "s/DESCRIPTION_PLACEHOLDER/$SERVICE_DESCRIPTION/g" app/config.py

mkdir -p app/routers

# Create app/routers/system.py
cat > app/routers/system.py <<'EOF'
from fastapi import APIRouter
from common import health_check_simple, liveness_probe_simple, readiness_probe_simple, HealthResponse, ServiceInfo, get_logger, StatusResponse
from app.config import SERVICE_NAME, SERVICE_VERSION, SERVICE_DESCRIPTION, START_TIME, ENVIRONMENT

router = APIRouter()
logger = get_logger(__name__).bind(service=SERVICE_NAME, environment=ENVIRONMENT)

@router.get("/health", response_model=HealthResponse)
async def health_check():
    return await health_check_simple(SERVICE_NAME, SERVICE_VERSION, START_TIME)

@router.get("/liveness", response_model=StatusResponse)
async def liveness_check():
    return await liveness_probe_simple()

@router.get("/readiness", response_model=StatusResponse)
async def readiness_check():
    return await readiness_probe_simple() 

@router.get("/status", response_model=ServiceInfo)
async def status():
    return ServiceInfo(
        service=SERVICE_NAME,
        version=SERVICE_VERSION,
        environment=ENVIRONMENT,
        description="SERVICE_DESCRIPTION",
    )

@router.get("/")
async def root():
    logger.info("root_endpoint_called")
    return {
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "message": f"Welcome to {SERVICE_NAME} service",
    }
EOF

# Create main.py
cat > main.py <<'EOF'
"""
SERVICE_NAME_PLACEHOLDER Service

DESCRIPTION_PLACEHOLDER
"""

import httpx
from contextlib import asynccontextmanager
from fastapi import FastAPI, APIRouter

from common import configure_logging, get_logger, LoggingMiddleware
from app.config import SERVICE_NAME, SERVICE_VERSION, ENVIRONMENT, LOG_LEVEL, PORT
from app.routers import system

# Configure logging immediately
configure_logging(log_level=LOG_LEVEL)
logger = get_logger(__name__).bind(service=SERVICE_NAME, environment=ENVIRONMENT)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("service_starting", service=SERVICE_NAME, version=SERVICE_VERSION, port=PORT)
    app.state.http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(30.0),
        limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
    )
    yield
    logger.info("service_stopping", service=SERVICE_NAME)
    await app.state.http_client.aclose()

app = FastAPI(
    title=f"{SERVICE_NAME} Service",
    description="DESCRIPTION_PLACEHOLDER",
    version=SERVICE_VERSION,
    lifespan=lifespan,
)

app.add_middleware(LoggingMiddleware)

# Assemble Routers
# Note: App Runner services typically don't need the dual-mount pattern
# (root + prefix) unless integrated with API Gateway
api_router = APIRouter()
api_router.include_router(system.router)

app.include_router(api_router)

# =============================================================================
# Development Server
# =============================================================================
# App Runner requires port 8080
# In production, this is started via the Dockerfile CMD

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
# App Runner REQUIRES port 8080
PORT=8080

# Observability (ADOT configuration via Terraform)
# The following are configured automatically by Terraform in App Runner:
# OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
# OTEL_SERVICE_NAME=$SERVICE_NAME
# OTEL_PROPAGATORS=xray
# OTEL_PYTHON_ID_GENERATOR=xray
# OTEL_METRICS_EXPORTER=none
# OTEL_RESOURCE_ATTRIBUTES=service.name=$SERVICE_NAME

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

@pytest.fixture(scope="module")
def client():
    """Create test client with lifespan context."""
    with TestClient(app) as test_client:
        yield test_client


# =============================================================================
# Health Check Tests
# =============================================================================

def test_health_check(client):
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data
    assert "uptime_seconds" in data

def test_liveness_probe(client) -> None:
    """Test liveness probe endpoint."""
    response = client.get("/liveness")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"

def test_readiness_probe(client) -> None:
    """Test readiness probe endpoint."""
    response = client.get("/readiness")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"


# =============================================================================
# General Endpoint Tests
# =============================================================================

def test_status(client):
    """Test status endpoint"""
    response = client.get("/status")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "SERVICE_NAME_PLACEHOLDER"
    assert "version" in data
    assert data["environment"] == "dev"

def test_root(client):
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "SERVICE_NAME_PLACEHOLDER"


# =============================================================================
# Documentation Endpoint Tests
# =============================================================================

def test_docs_endpoint(client):
    """Test Swagger UI docs endpoint"""
    response = client.get("/docs")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]

def test_openapi_json(client):
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

def test_redoc_endpoint(client):
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

# Run development server (port 8080 - App Runner requirement)
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

- \`GET /health\` - Health check (used by App Runner)
- \`GET /status\` - Service status
- \`GET /\` - Root endpoint

## Environment Variables

See \`.env.example\` for all available environment variables.

Required:
- \`SERVICE_NAME\` - Service identifier
- \`ENVIRONMENT\` - Environment (dev, test, prod)
- \`PROJECT_NAME\` - Project name (set by Terraform)
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
from shared import ServiceAPIClient, get_service_url

async with ServiceAPIClient(service_name="$SERVICE_NAME") as client:
    url = get_service_url("other-service")
    response = await client.get(f"{url}/endpoint")
\`\`\`

See [docs/API-KEYS-QUICKSTART.md](../../docs/API-KEYS-QUICKSTART.md) for API key setup.

## App Runner Specifics

- **Port**: Must listen on port 8080 (App Runner requirement)
- **Health Check**: App Runner uses \`/health\` endpoint by default
- **Tracing**: ADOT is installed in the container via Dockerfile
- **Scaling**: Configured via Terraform (min/max instances, concurrency)
- **No Lambda Handler**: App Runner runs uvicorn directly, no Mangum needed

## Differences from Lambda Services

| Feature | Lambda | App Runner |
|---------|--------|------------|
| Port | Any (via API Gateway) | **8080 (required)** |
| Handler | Mangum adapter required | Direct uvicorn |
| Base Image | AWS Lambda Python | python:3.14-slim |
| Startup | Lambda runtime | CMD in Dockerfile |
| Routing | Often needs dual-mount | Direct routing |
| OTEL Setup | Lambda Layer | Installed in container |

## Architecture

- **Runtime**: Python 3.14 on App Runner
- **Web Framework**: FastAPI with uvicorn
- **Observability**: OpenTelemetry + AWS X-Ray via ADOT
- **Logging**: Structured JSON logging
- **Deployment**: Docker container on AWS App Runner
EOF

echo "✅ Application files created"
echo ""

# =============================================================================
# Create Dockerfile for App Runner
# =============================================================================

echo "🐳 Creating Dockerfile..."

cat > Dockerfile.apprunner <<'EOF_DOCKER'
# =============================================================================
# App Runner Container Image for SERVICE_NAME Service
# =============================================================================
# Multi-architecture build for AWS App Runner
# Supports: linux/amd64, linux/arm64
# App Runner REQUIRES port 8080
# =============================================================================

# Multi-arch support - TARGETPLATFORM is automatically set by Docker BuildKit
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM python:3.14-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR /app

# Set environment variables for uv
ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1

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

# Install OpenTelemetry ADOT dependencies for automatic instrumentation
# ADOT provides automatic tracing for FastAPI, boto3, httpx, and more
RUN uv pip install --system --no-cache \
    "opentelemetry-distro[otlp]>=0.24b0" \
    "opentelemetry-sdk-extension-aws~=2.0" \
    "opentelemetry-propagator-aws-xray~=1.0"

# Run ADOT bootstrap to install automatic instrumentation packages
RUN opentelemetry-bootstrap --action=install

# Copy application code (all .py files except tests)
COPY backend/SERVICE_NAME/*.py ./
COPY backend/SERVICE_NAME/app ./app

# Remove test files
RUN rm -f test_*.py

# App Runner REQUIRES port 8080
EXPOSE 8080

# Health check endpoint (App Runner will use this)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Run application with OpenTelemetry automatic instrumentation
# The opentelemetry-instrument wrapper enables automatic tracing
# ADOT environment variables are configured via Terraform
CMD ["opentelemetry-instrument", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF_DOCKER

# Replace SERVICE_NAME placeholder with actual service name
sed -i "s/SERVICE_NAME/$SERVICE_NAME/g" Dockerfile.apprunner

echo "✅ Dockerfile created"
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
echo "   $SERVICE_DIR/app/config.py"
echo "   $SERVICE_DIR/app/routers/system.py"
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
echo "   ✅ boto3, pydantic, httpx"
echo "   ✅ pytest (dev)"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Start development server (port 8080):"
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
echo "⚡ App Runner Key Differences from Lambda:"
echo "   - ✅ Port 8080 is MANDATORY (App Runner requirement)"
echo "   - ✅ No Lambda handler/Mangum needed (direct uvicorn)"
echo "   - ✅ ADOT installed in container (not Lambda Layer)"
echo "   - ✅ Uses python:3.14-slim base (not Lambda base)"
echo "   - ✅ Direct routing (no dual-mount unless API Gateway integration)"
echo ""
echo "🎉 Happy coding!"
echo ""
