# AWS CodeArtifact Publication Plan for Shared Library

## Executive Summary

This document outlines the plan to publish the `shared` library to AWS CodeArtifact, transitioning from local editable installations to a centralized artifact repository. This enables versioned releases, better dependency management, and simplified CI/CD workflows.

## Quick Reference

| Item | Value |
|------|-------|
| **Package Name** | `agsys-common` |
| **Repository** | `agsys-python` |
| **Domain** | `agsys-dev` (dev) / `agsys` (prod) |
| **Region** | `us-east-1` |
| **Services Affected** | s3vector (Lambda) |
| **Initial Version** | `0.0.1` |

### Quick Start Commands

```bash
# Configure local environment for CodeArtifact
source <(./scripts/configure-codeartifact.sh)

# Build shared library
./scripts/build-shared-library.sh

# Publish to CodeArtifact
./scripts/publish-shared-library.sh

# Build service with CodeArtifact deps
./scripts/docker-build-with-codeartifact.sh <service-name>
```

## Current State

### Library Structure

- **Location**: `/backend/shared/` (will move to `/agsys/common/`)
- **Version**: 1.0.0 (current) → 0.0.1 (initial published version)
- **Package Name**: `shared` (current) → `agsys-common` (published)
- **Distribution Method**: Local editable install via `uv add --editable ../shared`
- **Current Consumers**:
  - **Lambda services**: s3vector (container image)
  - Note: api, api2, runner, runner2 are excluded from this migration

### Dependencies

```toml
dependencies = [
    "httpx>=0.27.0,<0.28.0",
    "boto3>=1.35.0,<2.0.0",
    "botocore>=1.35.0,<2.0.0",
    "pydantic>=2.9.0,<3.0.0",
    "pydantic-settings>=2.6.0,<3.0.0",
    "structlog>=24.4.0,<25.0.0",
    "opentelemetry-api>=1.27.0,<2.0.0",
    "opentelemetry-sdk>=1.27.0,<2.0.0",
    "opentelemetry-exporter-otlp-proto-grpc>=1.27.0,<2.0.0",
    "opentelemetry-instrumentation-fastapi>=0.48b0,<1.0.0",
    "opentelemetry-instrumentation-httpx>=0.48b0,<1.0.0",
]
```

### Current Modules

- `api_client.py` - Inter-service API client with auto API key injection
- `logging.py` - Structured logging configuration
- `tracing.py` - OpenTelemetry distributed tracing
- `middleware.py` - FastAPI middleware
- `models.py` - Common Pydantic models
- `settings.py` - Base settings classes
- `health.py` - Health check utilities

## Target State

### AWS CodeArtifact Repository

- **Repository Name**: `agsys-python`
- **Domain**: `agsys` (or organization-specific)
- **Package Format**: PyPI (Python)
- **Upstream**: PyPI public repository (for transitive dependencies)
- **Access**: IAM-based authentication

### Package Distribution

- **Package Name**: `agsys-common` (to avoid PyPI namespace conflicts)
- **Initial Version**: `0.0.1` (pre-release version)
- **Versioning**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Build System**: `setuptools` (already configured)
- **Distribution Format**: Wheel (`.whl`) and source distribution (`.tar.gz`)

## Implementation Plan

### Phase 1: AWS CodeArtifact Infrastructure Setup

#### 1.1 Create Terraform Resources

**File**: `terraform/codeartifact.tf`

```hcl
# AWS CodeArtifact Domain
resource "aws_codeartifact_domain" "main" {
  domain         = var.codeartifact_domain
  encryption_key = aws_kms_key.codeartifact.arn

  tags = {
    Name        = "${var.project_name}-codeartifact-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

# KMS Key for CodeArtifact encryption
resource "aws_kms_key" "codeartifact" {
  description             = "KMS key for CodeArtifact encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-codeartifact-kms"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "codeartifact" {
  name          = "alias/${var.project_name}-codeartifact"
  target_key_id = aws_kms_key.codeartifact.key_id
}

# Python Package Repository
resource "aws_codeartifact_repository" "python" {
  repository = "${var.project_name}-python"
  domain     = aws_codeartifact_domain.main.domain

  # Upstream PyPI for public packages
  external_connections {
    external_connection_name = "public:pypi"
  }

  tags = {
    Name        = "${var.project_name}-python-repo"
    Environment = var.environment
    Format      = "pypi"
  }
}

# IAM Policy for publishing packages
resource "aws_iam_policy" "codeartifact_publish" {
  name        = "${var.project_name}-codeartifact-publish"
  description = "Allow publishing to CodeArtifact repository"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codeartifact:PublishPackageVersion",
          "codeartifact:PutPackageMetadata",
        ]
        Resource = aws_codeartifact_repository.python.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
        ]
        Resource = [
          aws_codeartifact_repository.python.arn,
          aws_codeartifact_domain.main.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = "sts:GetServiceBearerToken"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      },
    ]
  })
}

# IAM Policy for reading packages (for Lambda and services)
resource "aws_iam_policy" "codeartifact_read" {
  name        = "${var.project_name}-codeartifact-read"
  description = "Allow reading from CodeArtifact repository"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codeartifact:GetPackageVersionReadme",
          "codeartifact:GetPackageVersionAsset",
          "codeartifact:ReadFromRepository",
          "codeartifact:ListPackages",
          "codeartifact:ListPackageVersions",
          "codeartifact:DescribePackageVersion",
        ]
        Resource = aws_codeartifact_repository.python.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
        ]
        Resource = [
          aws_codeartifact_repository.python.arn,
          aws_codeartifact_domain.main.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = "sts:GetServiceBearerToken"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      },
    ]
  })
}

# Attach read policy to Lambda execution role (shared across Lambda services)
# Note: Lambda services (api2, s3vector) use container images, so CodeArtifact
# access is only needed at Docker build time, not runtime.
# This attachment is for future non-container Lambda functions.
resource "aws_iam_role_policy_attachment" "lambda_codeartifact" {
  role       = "${var.project_name}-lambda-execution-role"  # Shared role from bootstrap
  policy_arn = aws_iam_policy.codeartifact_read.arn
}

# Attach read policy to AppRunner instance role (shared across AppRunner services)
# Note: AppRunner services (runner, runner2) also use container images from ECR,
# so CodeArtifact access is only needed at Docker build time, not runtime.
resource "aws_iam_role_policy_attachment" "apprunner_codeartifact" {
  role       = "${var.project_name}-apprunner-instance"  # Shared role from bootstrap
  policy_arn = aws_iam_policy.codeartifact_read.arn
}

# Output repository details
output "codeartifact_domain" {
  value       = aws_codeartifact_domain.main.domain
  description = "CodeArtifact domain name"
}

output "codeartifact_repository" {
  value       = aws_codeartifact_repository.python.repository
  description = "CodeArtifact Python repository name"
}

output "codeartifact_repository_endpoint" {
  value       = aws_codeartifact_repository.python.repository_endpoint
  description = "CodeArtifact repository endpoint URL"
}
```

#### 1.2 Add Variables

**File**: `terraform/variables.tf` (additions)

```hcl
variable "codeartifact_domain" {
  description = "CodeArtifact domain name"
  type        = string
  default     = "agsys"
}
```

**File**: `terraform/environments/dev.tfvars` (additions)

```hcl
codeartifact_domain = "agsys-dev"
```

### Phase 2: Package Configuration Updates

#### 2.1 Restructure and Update Package

##### Step 1: Move directory structure

```bash
# Move from backend/shared to agsys/common
mkdir -p agsys
mv backend/shared agsys/common
```

##### Step 2: Update pyproject.toml

**File**: `agsys/common/pyproject.toml`

Changes needed:

1. Rename package from `shared` to `agsys-common`
2. Set initial version to `0.0.1`
3. Add metadata (authors, license, readme, repository)
4. Configure build system properly
5. Add classifiers

```toml
[project]
name = "agsys-common"  # Changed from "shared"
version = "0.0.1"      # Initial pre-release version
description = "Common library for agsys backend services"
readme = "README.md"
requires-python = ">=3.14"
license = { text = "MIT" }
authors = [
    { name = "Guilherme Azevedo", email = "gpazevedo@users.noreply.github.com" }
]
keywords = ["aws", "lambda", "fastapi", "common-library"]

classifiers = [
    "Development Status :: 3 - Alpha",
    "Intended Audience :: Developers",
    "Programming Language :: Python :: 3.14",
    "Framework :: FastAPI",
    "Topic :: Software Development :: Libraries",
]

# Repository information
[project.urls]
Repository = "https://github.com/gpazevedo/fin-advisor"
Documentation = "https://github.com/gpazevedo/fin-advisor/tree/main/docs"

# Dependencies remain the same
dependencies = [
    # ... existing dependencies ...
]

[build-system]
requires = ["setuptools>=68.0", "wheel"]
build-backend = "setuptools.build_meta"

[tool.setuptools]
packages = ["common"]

[tool.setuptools.package-dir]
common = "."
```

#### 2.2 Add Package Metadata Files

**File**: `agsys/common/LICENSE`

```text
MIT License (or your chosen license)
```

**File**: `agsys/common/MANIFEST.in`

```text
include README.md
include LICENSE
recursive-include common *.py
```

**File**: `agsys/common/README.md`

```markdown
# agsys-common

Common library for agsys backend services.

## Installation

```bash
pip install agsys-common
```

## Features

- Structured logging with structlog
- OpenTelemetry distributed tracing
- FastAPI middleware
- Health check utilities
- Inter-service API client with automatic API key injection
```
```

### Phase 3: Build and Publish Scripts

#### 3.1 Build Script

**File**: `scripts/build-common-library.sh`

```bash
#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building agsys-common library package...${NC}"

cd agsys/common

# Clean previous builds
rm -rf dist/ build/ *.egg-info/

# Build the package
python -m pip install --upgrade build
python -m build

echo -e "${GREEN}✓ Package built successfully${NC}"
echo "Distributions created:"
ls -lh dist/

# Show package info
echo -e "\n${BLUE}Package information:${NC}"
python -m pip show setuptools || true
tar -tzf dist/*.tar.gz | head -20
```

#### 3.2 Publish Script

**File**: `scripts/publish-common-library.sh`

```bash
#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
DOMAIN="${CODEARTIFACT_DOMAIN:-agsys-dev}"
REPOSITORY="${CODEARTIFACT_REPOSITORY:-agsys-python}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo -e "${BLUE}Publishing agsys-common library to AWS CodeArtifact...${NC}"

# Check if package is built
if [ ! -d "agsys/common/dist" ]; then
    echo -e "${YELLOW}Package not built. Running build first...${NC}"
    ./scripts/build-common-library.sh
fi

cd agsys/common

# Get CodeArtifact authentication token
echo -e "${BLUE}Getting CodeArtifact authentication token...${NC}"
export TWINE_USERNAME=aws
export TWINE_PASSWORD=$(aws codeartifact get-authorization-token \
    --domain "$DOMAIN" \
    --domain-owner "$(aws sts get-caller-identity --query Account --output text)" \
    --region "$AWS_REGION" \
    --query authorizationToken \
    --output text)

# Get repository endpoint
REPO_ENDPOINT=$(aws codeartifact get-repository-endpoint \
    --domain "$DOMAIN" \
    --domain-owner "$(aws sts get-caller-identity --query Account --output text)" \
    --repository "$REPOSITORY" \
    --format pypi \
    --region "$AWS_REGION" \
    --query repositoryEndpoint \
    --output text)

export TWINE_REPOSITORY_URL="${REPO_ENDPOINT}"

# Install twine if not available
python -m pip install --upgrade twine

# Upload to CodeArtifact
echo -e "${BLUE}Uploading package to CodeArtifact...${NC}"
python -m twine upload --repository codeartifact dist/*

echo -e "${GREEN}✓ Package published successfully to CodeArtifact${NC}"
echo -e "Domain: ${DOMAIN}"
echo -e "Repository: ${REPOSITORY}"
echo -e "Region: ${AWS_REGION}"

# List package versions
echo -e "\n${BLUE}Verifying package versions in repository:${NC}"
aws codeartifact list-package-versions \
    --domain "$DOMAIN" \
    --repository "$REPOSITORY" \
    --format pypi \
    --package agsys-common \
    --region "$AWS_REGION" \
    --query 'versions[*].[version,status]' \
    --output table
```

#### 3.3 Version Bump Script

**File**: `scripts/bump-common-version.sh`

```bash
#!/bin/bash
set -euo pipefail

# Semantic version bump script
VERSION_TYPE="${1:-patch}"  # major, minor, or patch

if [[ ! "$VERSION_TYPE" =~ ^(major|minor|patch)$ ]]; then
    echo "Usage: $0 [major|minor|patch]"
    exit 1
fi

PYPROJECT="agsys/common/pyproject.toml"
INIT_FILE="agsys/common/__init__.py"

# Get current version
CURRENT_VERSION=$(grep '^version = ' "$PYPROJECT" | cut -d'"' -f2)
echo "Current version: $CURRENT_VERSION"

# Parse version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Bump version
case "$VERSION_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "New version: $NEW_VERSION"

# Update files
sed -i "s/^version = .*/version = \"$NEW_VERSION\"/" "$PYPROJECT"
sed -i "s/^__version__ = .*/__version__ = \"$NEW_VERSION\"/" "$INIT_FILE"

echo "✓ Version updated to $NEW_VERSION"
echo "Don't forget to commit the changes!"
```

### Phase 4: Service Consumer Updates

#### 4.1 Configure uv to Use CodeArtifact

**Important**: Both `pip` and `uv` need proper configuration to authenticate with CodeArtifact.

##### Option A: Using AWS CodeArtifact Login (Recommended)

AWS CLI provides a built-in command that configures pip automatically:

```bash
# Configure pip/uv for CodeArtifact (token valid for 12 hours)
aws codeartifact login \
    --tool pip \
    --domain agsys-dev \
    --repository agsys-python \
    --region us-east-1

# For uv specifically, also set:
export UV_INDEX_URL=$(aws codeartifact get-repository-endpoint \
    --domain agsys-dev \
    --repository agsys-python \
    --format pypi \
    --query repositoryEndpoint \
    --output text)simple/
```

##### Option B: Environment Variables (CI/CD)

```bash
export AWS_CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token \
    --domain agsys-dev \
    --query authorizationToken \
    --output text)

# For pip
export PIP_INDEX_URL=https://aws:${AWS_CODEARTIFACT_AUTH_TOKEN}@agsys-dev-123456789012.d.codeartifact.us-east-1.amazonaws.com/pypi/agsys-python/simple/

# For uv (uses different env vars)
export UV_INDEX_URL="${PIP_INDEX_URL}"
export UV_EXTRA_INDEX_URL=https://pypi.org/simple/
```

##### Option C: Helper Script

**File**: `scripts/configure-codeartifact.sh`

```bash
#!/bin/bash
set -euo pipefail

DOMAIN="${CODEARTIFACT_DOMAIN:-agsys-dev}"
REPOSITORY="${CODEARTIFACT_REPOSITORY:-agsys-python}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Get authentication token (valid for 12 hours)
TOKEN=$(aws codeartifact get-authorization-token \
    --domain "$DOMAIN" \
    --query authorizationToken \
    --output text \
    --region "$AWS_REGION")

# Get repository endpoint
ENDPOINT=$(aws codeartifact get-repository-endpoint \
    --domain "$DOMAIN" \
    --repository "$REPOSITORY" \
    --format pypi \
    --region "$AWS_REGION" \
    --query repositoryEndpoint \
    --output text)

INDEX_URL="${ENDPOINT}simple/"

# Output for sourcing
cat << EOF
# CodeArtifact configuration (token expires in 12 hours)
# Run: source <(./scripts/configure-codeartifact.sh)

# pip configuration
export PIP_INDEX_URL='${INDEX_URL}'
export PIP_EXTRA_INDEX_URL='https://pypi.org/simple/'

# uv configuration
export UV_INDEX_URL='${INDEX_URL}'
export UV_EXTRA_INDEX_URL='https://pypi.org/simple/'

echo "✓ CodeArtifact configured for domain: ${DOMAIN}"
EOF
```

Usage:

```bash
# Source the script to set environment variables
source <(./scripts/configure-codeartifact.sh)

# Now uv/pip commands will use CodeArtifact
uv sync
```

#### 4.2 Local Development Workflow

During development, you may want to test local changes to the shared library before publishing.

**Hybrid approach** (recommended):

1. **Local development**: Use editable install for rapid iteration

   ```bash
   cd backend/api2
   uv add --editable ../shared
   ```

2. **Before commit**: Switch to CodeArtifact version to verify compatibility

   ```bash
   cd backend/api2
   uv remove shared
   source <(./scripts/configure-codeartifact.sh)
   uv add "agsys-shared>=1.0.0,<2.0.0"
   ```

3. **CI/CD**: Always uses CodeArtifact (no editable installs)

#### 4.3 Update Service Dependencies

For the s3vector service only:

**Before** (`backend/s3vector/pyproject.toml`):

```toml
dependencies = [
    # ... other deps ...
    "shared",
]

[tool.uv.sources]
shared = { path = "../shared", editable = true }
```

**After** (`backend/s3vector/pyproject.toml`):

```toml
dependencies = [
    # ... other deps ...
    "agsys-common>=0.0.1,<1.0.0",
]

# Remove [tool.uv.sources] section
```

**Note**: Services api, api2, runner, and runner2 will continue using local editable installs and are not part of this migration.

#### 4.4 Update Service Creation Scripts

The service creation scripts must be updated so that new services automatically use the agsys-common package from CodeArtifact.

**Files to update**:

- `scripts/create-lambda-service.sh`
- `scripts/create-apprunner-service.sh`

**Current behavior** (lines ~107-113 in both scripts):

```bash
# Add shared library as editable dependency
echo "📚 Adding shared library..."
uv add --editable ../shared
```

**New behavior**:

```bash
# Add common library from CodeArtifact
echo "📚 Adding agsys-common library from CodeArtifact..."

# Check if CodeArtifact is configured
if [ -z "$UV_INDEX_URL" ]; then
    echo "⚠️  CodeArtifact not configured. Configuring now..."
    if [ -f "./scripts/configure-codeartifact.sh" ]; then
        source <(./scripts/configure-codeartifact.sh)
    else
        echo "❌ Error: CodeArtifact configuration script not found"
        echo "   Run: ./scripts/configure-codeartifact.sh"
        exit 1
    fi
fi

uv add "agsys-common>=0.0.1,<1.0.0"
```

**Dockerfile updates** (both `Dockerfile.lambda` and `Dockerfile.apprunner`):

Current Dockerfiles copy the local shared library and fix paths. After migration, they should use CodeArtifact:

```dockerfile
# REMOVE these lines:
# COPY backend/shared/ ./shared/
# RUN sed -i 's|path = "../shared"|path = "./shared"|g' pyproject.toml

# ADD CodeArtifact authentication:
ARG CODEARTIFACT_INDEX_URL
ENV UV_INDEX_URL=${CODEARTIFACT_INDEX_URL}
ENV UV_EXTRA_INDEX_URL=https://pypi.org/simple/
```

**Import statement updates in generated main.py**:

```python
# Change from:
from shared import (...)

# To:
from common import (...)
```

**Script changes summary**:

| Script | Change |
|--------|--------|
| `create-lambda-service.sh` | Replace `uv add --editable ../shared` with `uv add "agsys-common>=0.0.1,<1.0.0"` |
| `create-apprunner-service.sh` | Replace `uv add --editable ../shared` with `uv add "agsys-common>=0.0.1,<1.0.0"` |
| Generated `Dockerfile.lambda` | Remove shared library copy, add `CODEARTIFACT_INDEX_URL` build arg |
| Generated `Dockerfile.apprunner` | Remove shared library copy, add `CODEARTIFACT_INDEX_URL` build arg |
| Generated `main.py` | Change imports from `shared` to `common` |
| Generated `pyproject.toml` | No `[tool.uv.sources]` section needed |
| Generated `README.md` | Update dependency installation instructions |

**Build command update** (in generated README and summary):

```bash
# Old:
./scripts/docker-push.sh dev $SERVICE_NAME Dockerfile.lambda

# New:
./scripts/docker-build-with-codeartifact.sh $SERVICE_NAME
./scripts/docker-push.sh dev $SERVICE_NAME
```

### Phase 5: CI/CD Integration

#### 5.1 GitHub Actions Workflow

**File**: `.github/workflows/publish-shared-library.yml`

```yaml
name: Publish Shared Library

on:
  push:
    branches:
      - main
    paths:
      - 'backend/shared/**'
      - '.github/workflows/publish-shared-library.yml'
  workflow_dispatch:
    inputs:
      version_bump:
        description: 'Version bump type'
        required: true
        default: 'patch'
        type: choice
        options:
          - major
          - minor
          - patch

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.14'

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: us-east-1

      - name: Bump version
        if: github.event_name == 'workflow_dispatch'
        run: |
          ./scripts/bump-shared-version.sh ${{ inputs.version_bump }}
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          NEW_VERSION=$(grep '^version = ' backend/shared/pyproject.toml | cut -d'"' -f2)
          git add backend/shared/pyproject.toml backend/shared/__init__.py
          git commit -m "Bump shared library version to $NEW_VERSION"
          git push

      - name: Build package
        run: ./scripts/build-shared-library.sh

      - name: Publish to CodeArtifact
        env:
          CODEARTIFACT_DOMAIN: agsys-dev
          CODEARTIFACT_REPOSITORY: agsys-python
          AWS_REGION: us-east-1
        run: ./scripts/publish-shared-library.sh

      - name: Create Git tag
        if: github.event_name == 'workflow_dispatch'
        run: |
          VERSION=$(grep '^version = ' backend/shared/pyproject.toml | cut -d'"' -f2)
          git tag "shared-v$VERSION"
          git push origin "shared-v$VERSION"
```

#### 5.2 Docker Build Updates

For services using Docker (Lambda containers, AppRunner), there are two approaches:

##### Option A: Build-time Authentication (Simpler)

Pass the CodeArtifact token as a build argument. The token is generated before build and passed in.

**File**: `backend/runner/Dockerfile` (example)

```dockerfile
FROM python:3.14-slim

WORKDIR /app

# Install uv for fast dependency resolution
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies using pre-authenticated index URL
# The CODEARTIFACT_INDEX_URL is passed at build time
ARG CODEARTIFACT_INDEX_URL
ENV UV_INDEX_URL=${CODEARTIFACT_INDEX_URL}
ENV UV_EXTRA_INDEX_URL=https://pypi.org/simple/

RUN uv sync --frozen --no-dev

# Copy application code
COPY . .

EXPOSE 8080
CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Build command** (in CI/CD or locally):

```bash
# Get authenticated index URL
CODEARTIFACT_INDEX_URL=$(aws codeartifact get-repository-endpoint \
    --domain agsys-dev \
    --repository agsys-python \
    --format pypi \
    --query repositoryEndpoint \
    --output text)simple/

TOKEN=$(aws codeartifact get-authorization-token \
    --domain agsys-dev \
    --query authorizationToken \
    --output text)

# Build with authenticated URL (token embedded in URL)
docker build \
    --build-arg CODEARTIFACT_INDEX_URL="https://aws:${TOKEN}@${CODEARTIFACT_INDEX_URL#https://}" \
    -t my-service .
```

##### Option B: Multi-stage Build with Secrets (More Secure)

For builds that shouldn't expose tokens in layer history:

```dockerfile
FROM python:3.14-slim AS builder

WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock ./

# Use Docker BuildKit secrets (token not stored in image layers)
RUN --mount=type=secret,id=codeartifact_url \
    UV_INDEX_URL=$(cat /run/secrets/codeartifact_url) \
    UV_EXTRA_INDEX_URL=https://pypi.org/simple/ \
    uv sync --frozen --no-dev

FROM python:3.14-slim
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY . .
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Build command**:

```bash
# Create secret file with authenticated URL
echo "https://aws:${TOKEN}@${CODEARTIFACT_INDEX_URL#https://}" > /tmp/codeartifact_url

DOCKER_BUILDKIT=1 docker build \
    --secret id=codeartifact_url,src=/tmp/codeartifact_url \
    -t my-service .

rm /tmp/codeartifact_url
```

##### Docker Build Script

**File**: `scripts/docker-build-with-codeartifact.sh`

```bash
#!/bin/bash
set -euo pipefail

SERVICE="${1:?Usage: $0 <service-name>}"
DOMAIN="${CODEARTIFACT_DOMAIN:-agsys-dev}"
REPOSITORY="${CODEARTIFACT_REPOSITORY:-agsys-python}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "Building ${SERVICE} with CodeArtifact dependencies..."

# Get CodeArtifact authentication
TOKEN=$(aws codeartifact get-authorization-token \
    --domain "$DOMAIN" \
    --query authorizationToken \
    --output text \
    --region "$AWS_REGION")

ENDPOINT=$(aws codeartifact get-repository-endpoint \
    --domain "$DOMAIN" \
    --repository "$REPOSITORY" \
    --format pypi \
    --query repositoryEndpoint \
    --output text \
    --region "$AWS_REGION")

# Construct authenticated URL
AUTH_URL="https://aws:${TOKEN}@${ENDPOINT#https://}simple/"

# Build the image
docker build \
    --build-arg CODEARTIFACT_INDEX_URL="${AUTH_URL}" \
    -t "${SERVICE}:latest" \
    "backend/${SERVICE}"

echo "✓ Built ${SERVICE}:latest"
```

### Phase 6: Lambda Layer Updates (Future Option)

> **Note**: This section is for reference only. Lambda Layers are **not compatible** with container image deployments (which this project uses). This approach would only apply if migrating to ZIP-based Lambda deployments in the future.

For ZIP-based Lambda deployments, consider using Lambda Layers instead of including the shared library in each deployment package:

#### 6.1 Create Lambda Layer with Shared Library

**File**: `scripts/build-shared-lambda-layer.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "Building Lambda Layer for shared library..."

LAYER_DIR="build/lambda-layer"
rm -rf "$LAYER_DIR"
mkdir -p "$LAYER_DIR/python"

# Install shared library from CodeArtifact
cd "$LAYER_DIR"

# Configure CodeArtifact
source ../../scripts/configure-codeartifact.sh

pip install \
    --target python/ \
    --platform manylinux2014_x86_64 \
    --python-version 3.14 \
    --only-binary=:all: \
    agsys-shared

# Create layer zip
cd python
zip -r ../shared-layer.zip .

echo "✓ Lambda layer created: $LAYER_DIR/shared-layer.zip"
```

#### 6.2 Terraform for Lambda Layer

**File**: `terraform/lambda-shared-layer.tf`

```hcl
resource "aws_lambda_layer_version" "shared" {
  filename            = "${path.module}/../build/lambda-layer/shared-layer.zip"
  layer_name          = "${var.project_name}-shared"
  compatible_runtimes = ["python3.14"]
  source_code_hash    = filebase64sha256("${path.module}/../build/lambda-layer/shared-layer.zip")

  description = "Shared library for agsys services"
}

# Update Lambda functions to use the layer
resource "aws_lambda_function" "api" {
  # ... existing config ...

  layers = [
    aws_lambda_layer_version.shared.arn
  ]
}
```

## Versioning Strategy

### Semantic Versioning

- **MAJOR** (1.x.x): Breaking changes to public API
- **MINOR** (x.1.x): New features, backward compatible
- **PATCH** (x.x.1): Bug fixes, backward compatible

### Version Constraints in Services

```toml
# Recommended: Allow minor and patch updates
"agsys-shared>=1.0.0,<2.0.0"

# Conservative: Lock to specific minor version
"agsys-shared>=1.2.0,<1.3.0"

# Development: Use exact version for testing
"agsys-shared==1.2.3"
```

### Deprecation Policy

1. Mark deprecated features with warnings (1 minor version)
2. Remove deprecated features in next major version
3. Document all breaking changes in CHANGELOG.md

## Testing Strategy

### Pre-publish Tests

```bash
# In backend/shared/
pytest tests/ -v
ruff check .
pyright .
```

### Integration Testing

1. Publish to dev CodeArtifact repository
2. Update one service to use published version
3. Run service integration tests
4. Deploy to dev environment
5. Verify functionality
6. Promote to production CodeArtifact if successful

## Migration Path

### Pre-flight Checklist

Before starting migration, verify:

- [ ] AWS credentials configured with CodeArtifact permissions
- [ ] Terraform state accessible and up-to-date
- [ ] All services passing tests with current editable install
- [ ] GitHub Actions has `AWS_DEPLOY_ROLE_ARN` secret configured
- [ ] Docker BuildKit enabled (`DOCKER_BUILDKIT=1`)
- [ ] Team notified of upcoming changes

### Step 1: Infrastructure Setup

1. Create Terraform resources for CodeArtifact
2. Apply to dev environment: `make app-init-dev app-apply-dev`
3. Test authentication: `aws codeartifact get-authorization-token --domain agsys-dev`
4. Verify repository endpoint accessible

### Step 2: Package Preparation

1. Move library directory: `mkdir -p agsys && mv backend/shared agsys/common`
2. Update `agsys/common/pyproject.toml`:
   - Change name to `agsys-common`
   - Set version to `0.0.1`
   - Update package directory to `common`
   - Add metadata (authors: Guilherme Azevedo, repository: github.com/gpazevedo/fin-advisor)
3. Add `LICENSE`, `MANIFEST.in`, and `README.md` files to `agsys/common/`
4. Create build and publish scripts:
   - `scripts/build-common-library.sh`
   - `scripts/publish-common-library.sh`
   - `scripts/bump-common-version.sh`
   - `scripts/configure-codeartifact.sh`
   - `scripts/docker-build-with-codeartifact.sh`
5. Test local build: `./scripts/build-common-library.sh`
6. Verify wheel and sdist created in `agsys/common/dist/`

### Step 3: First Publication

1. Publish version 0.0.1 to dev CodeArtifact: `./scripts/publish-common-library.sh`

2. Verify package in repository:

   ```bash
   aws codeartifact list-package-versions \
       --domain agsys-dev \
       --repository agsys-python \
       --format pypi \
       --package agsys-common
   ```

3. Test installation from CodeArtifact:

   ```bash
   source <(./scripts/configure-codeartifact.sh)
   pip install agsys-common
   ```

### Step 4: Migrate s3vector Service

1. **Update s3vector** (Lambda):
   - Update `backend/s3vector/pyproject.toml`:
     - Change dependency from `"shared"` to `"agsys-common>=0.0.1,<1.0.0"`
     - Remove `[tool.uv.sources]` section
   - Update imports in `backend/s3vector/main.py`: Change `from shared import ...` to `from common import ...`
   - Test locally with CodeArtifact: `cd backend/s3vector && source <(../../scripts/configure-codeartifact.sh) && uv sync`
   - Build Docker image: `./scripts/docker-build-with-codeartifact.sh s3vector`
   - Deploy to dev: Push image and run `make app-init-dev app-apply-dev`
   - Verify service operational

**Note**: Services api, api2, runner, and runner2 are not being migrated and will continue using local editable installs.

### Step 5: Update Service Creation Scripts

1. Update `scripts/create-lambda-service.sh`:
   - Replace `uv add --editable ../shared` with `uv add "agsys-common>=0.0.1,<1.0.0"`
   - Update generated `Dockerfile.lambda` template to use CodeArtifact (add build args)
   - Change generated imports from `from shared import` to `from common import`
   - Update generated `README.md` with new build commands
2. Update `scripts/create-apprunner-service.sh`:
   - Replace `uv add --editable ../shared` with `uv add "agsys-common>=0.0.1,<1.0.0"`
   - Update generated `Dockerfile.apprunner` template to use CodeArtifact (add build args)
   - Change generated imports from `from shared import` to `from common import`
   - Update generated `README.md` with new build commands
3. Test by creating a new service: `./scripts/create-lambda-service.sh testservice`
4. Verify new service:
   - Uses `agsys-common` package instead of editable install
   - Imports from `common` module
   - Builds correctly with CodeArtifact authentication

### Step 6: CI/CD Automation

1. Set up GitHub Actions workflow for automated publishing
2. Test automated publishing with a patch version bump
3. Update existing service deployment workflows to authenticate with CodeArtifact
4. Document process for developers

### Step 7: Production Deployment

1. Create production CodeArtifact domain/repository (or use same domain with different access)
2. Publish 1.0.0 to production repository
3. Deploy services to production
4. Monitor CloudWatch for any issues
5. Verify health checks passing

### Rollback Procedure

If issues occur after migration:

1. **Quick rollback**: Pin services to previous working version

   ```toml
   "agsys-shared==1.0.0"
   ```

2. **Full rollback**: Revert to editable installs

   ```bash
   # In each service directory
   uv remove agsys-shared
   uv add --editable ../shared
   ```

3. **Delete problematic version** (if needed):

   ```bash
   aws codeartifact delete-package-versions \
       --domain agsys-dev \
       --repository agsys-python \
       --format pypi \
       --package agsys-shared \
       --versions 1.2.3
   ```

## Cost Considerations

### AWS CodeArtifact Pricing (us-east-1)

- **Storage**: $0.05 per GB-month
- **Requests**: $0.05 per 10,000 requests
- **Data Transfer**: Standard AWS data transfer rates

### Estimated Monthly Costs

- Storage: ~10 MB for shared library = $0.001/month
- Requests: ~1,000 pulls/month = $0.005/month
- **Total**: < $0.01/month (negligible)

### Compared to Alternatives

- PyPI: Free but public
- Self-hosted: ~$10-20/month for EC2 + storage
- GitHub Packages: $0 for public, usage-based for private

## Security Considerations

### Access Control

- Use IAM policies for fine-grained access
- Separate read/write permissions
- Use IAM roles for CI/CD (no long-lived credentials)

### Package Integrity

- Enable domain/repository encryption with KMS
- Use CodeArtifact package origin controls
- Sign packages (optional)

### Secret Management

- Store CodeArtifact credentials in AWS Secrets Manager
- Rotate tokens regularly (12-hour expiration)
- Use OIDC for GitHub Actions authentication

## Monitoring and Observability

### CloudWatch Metrics

- Package download count
- Package upload success/failure
- API request latency

### Alerts

- Failed package publications
- Unusual download patterns
- Storage quota approaching limit

### Logging

```python
# In publish script
aws codeartifact put-package-metadata \
    --domain agsys-dev \
    --repository agsys-python \
    --format pypi \
    --package agsys-shared \
    --version 1.0.0 \
    --metadata file://package-metadata.json
```

## Documentation Requirements

### For Developers

1. **CODEARTIFACT-SETUP.md**: How to configure local environment
2. **SHARED-LIBRARY-PUBLISH.md**: How to publish new versions
3. **SHARED-LIBRARY-CONSUME.md**: How to use in services
4. Update **SHARED-LIBRARY.md**: Add CodeArtifact installation instructions

### CHANGELOG.md

Maintain a changelog in `backend/shared/CHANGELOG.md`:

```markdown
# Changelog

## [1.1.0] - 2025-XX-XX
### Added
- New feature X

### Changed
- Updated API client timeout handling

### Fixed
- Bug in health check endpoint

## [1.0.0] - 2025-XX-XX
### Initial Release
- API client with auto API key injection
- Structured logging and tracing
- Health check utilities
```

## Alternatives Considered

### 1. Keep Local Editable Install

**Pros**: Simple, no infrastructure
**Cons**: No versioning, difficult CI/CD, no isolation

### 2. Git Submodules

**Pros**: Version control
**Cons**: Complex workflow, no package management

### 3. Private PyPI Server

**Pros**: Standard PyPI interface
**Cons**: Maintenance overhead, costs

### 4. GitHub Packages

**Pros**: Integrated with GitHub
**Cons**: Less AWS integration, different pricing

**Decision**: AWS CodeArtifact for native AWS integration and minimal overhead

## Success Criteria

- [ ] Library moved from `backend/shared` to `agsys/common`
- [ ] Package renamed to `agsys-common` with version `0.0.1`
- [ ] Package published to CodeArtifact
- [ ] s3vector service migrated to use `agsys-common` from CodeArtifact
- [ ] s3vector imports updated from `shared` to `common`
- [ ] Service creation scripts updated (`create-lambda-service.sh`, `create-apprunner-service.sh`)
- [ ] New services automatically use `agsys-common` from CodeArtifact
- [ ] New services use `from common import` instead of `from shared import`
- [ ] CI/CD pipeline automated for publishing
- [ ] Documentation complete (setup, publish, consume guides)
- [ ] Development workflow documented and tested
- [ ] Version management in place with CHANGELOG

**Note**: Services api, api2, runner, and runner2 remain on local editable installs and are excluded from migration.

## Open Questions

| Question | Options | Recommendation |
|----------|---------|----------------|
| **Domain naming** | `agsys` vs organization-wide | Use `agsys` for isolation; can migrate to org domain later |
| **Multi-region** | Single vs multiple regions | Start with `us-east-1` only; add regions if latency becomes an issue |
| **Upstream repos** | PyPI allowed vs CodeArtifact only | Allow PyPI upstream for public packages (already configured) |
| **Lambda deployment** | Lambda Layer vs container package | Use container package (current approach); Layers don't work with container images |
| **Version pinning** | Flexible `>=1.0,<2.0` vs strict `==1.0.0` | Use flexible ranges in dev, consider stricter pins for production |

## References

- [AWS CodeArtifact Documentation](https://docs.aws.amazon.com/codeartifact/)
- [Python Packaging User Guide](https://packaging.python.org/)
- [Semantic Versioning](https://semver.org/)
- [uv Documentation](https://github.com/astral-sh/uv)
