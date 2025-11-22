# AWS Bootstrap Infrastructure

> **A starter for Python cloud applications on AWS**

A production-ready Infrastructure as Code (IaC) template for bootstrapping AWS projects. Supports Python 3.13 with `uv` for fast dependency management, GitHub Actions CI/CD via OIDC, and Terraform state management in S3.

**📖 New to this project?** Start with the [Terraform Bootstrap Guide](docs/TERRAFORM-BOOTSTRAP.md) for a complete walkthrough.

---

## 📚 Table of Contents

- [🚀 Features](#-features)
- [🎯 Which Compute Option Should I Choose?](#-which-compute-option-should-i-choose)
- [📋 Prerequisites](#-prerequisites)
- [🏗️ Architecture](#️-architecture)
- [🚀 Quick Start](#-quick-start-1)
  - [1. Clone and Setup](#1-clone-and-setup)
  - [2. Configure Your Project](#2-configure-your-project)
  - [3. Deploy Bootstrap Infrastructure](#3-deploy-bootstrap-infrastructure)
  - [4. Deploy Your Application](#4-deploy-your-application)
  - [5. Configure GitHub Actions](#5-configure-github-actions-optional)
  - [6. Setup Code Quality](#6-setup-code-quality-optional)
  - [7. Push to GitHub](#7-push-to-github)
- [🧪 Testing & Deployment](#-testing--deployment)
  - [Local Testing](#local-testing)
  - [Deploy to AWS](#deploy-to-aws)
  - [Deployment Workflow Summary](#deployment-workflow-summary)
- [📝 Configuration Examples](#-configuration-examples)
- [🏗️ Multi-Service Backend Structure](#️-multi-service-backend-structure)
- [🐍 Python Development with uv](#-python-development-with-uv)
- [🔧 Make Commands](#-make-commands)
- [📁 Directory Structure](#-directory-structure)
- [🔐 Security Best Practices](#-security-best-practices)
- [🎯 Use Cases](#-use-cases)
- [📊 Cost Estimates](#-cost-estimates)
- [🆘 Troubleshooting](#-troubleshooting)
- [📚 Documentation](#-documentation)
- [📞 Support](#-support)

---

## 🚀 Features

### Compute Options (Choose Your Stack)
- **✅ Lambda** - Serverless functions with container images (default)
- **🌐 App Runner** - Fully managed containerized web applications
- **☸️ EKS** - Kubernetes-based container orchestration platform

### Core Capabilities
- **📦 Python 3.13 + uv** - Latest Python with ultra-fast dependency management
- **🔐 GitHub OIDC** - Secure, credential-less CI/CD authentication
- **🗄️ S3 State Management** - Self-referencing Terraform state with locking
- **🎯 Multi-Environment** - Dev, test, and prod environments
- **🐳 Container-Ready** - ECR repositories with vulnerability scanning
- **🌐 API Gateway Standard** - Centralized API entry point with rate limiting, security, and observability
- **🔑 API Key Authentication** - Optional API key authentication with usage plans and quotas

### Infrastructure Included
- S3 bucket for Terraform state (versioned, encrypted)
- GitHub Actions OIDC provider
- IAM roles per environment (dev, test, prod)
- ECR repositories (conditional)
- Lambda execution roles (conditional)
- App Runner access & instance roles (conditional)
- EKS cluster with node groups (conditional)

---

## 🎯 Which Compute Option Should I Choose?

Use this decision guide to select the right infrastructure for your project:

```
START HERE
    ↓
┌─────────────────────────────────────────────────┐
│ What type of workload are you building?         │
└─────────────────────────────────────────────────┘
    ↓
    ├─→ REST API, scheduled jobs, event processing
    │   ├─→ Runtime < 15 minutes? → YES → ✅ Lambda
    │   └─→ Runtime > 15 minutes? → YES → App Runner or EKS
    │
    ├─→ Web application, long-running processes
    │   ├─→ Simple deployment? → YES → ✅ App Runner
    │   └─→ Need full control? → YES → EKS
    │
    └─→ Complex microservices, orchestration needs
        └─→ ✅ EKS
```

### Quick Decision Matrix

| Question | Lambda | App Runner | EKS |
|----------|--------|------------|-----|
| **Runtime limit** | < 15 min | Unlimited | Unlimited |
| **Cold starts** | Yes (1-3s) | Minimal | None |
| **Scaling** | Automatic | Automatic | Manual/HPA |
| **Cost (small app)** | $5-50/mo | $20-100/mo | $150-500/mo |
| **Complexity** | Low | Low | High |
| **Best for** | APIs, jobs | Web apps | Microservices |
| **Kubernetes needed?** | No | No | Yes |
| **Container support** | Yes | Yes | Yes |
| **VPC required?** | Optional | Optional | Yes |

### Detailed Recommendations

**Choose Lambda if:**
- ✅ You're building REST APIs, webhooks, or scheduled tasks
- ✅ Your functions complete in < 15 minutes
- ✅ You want the lowest cost for variable traffic
- ✅ You prefer serverless (no server management)
- ❌ Cold starts (1-3 seconds) are acceptable

**Choose App Runner if:**
- ✅ You're building web applications or APIs
- ✅ You need long-running processes (> 15 minutes)
- ✅ You want simple container deployment
- ✅ You need auto-scaling with minimal configuration
- ❌ You don't need Kubernetes features

**Choose EKS if:**
- ✅ You have complex microservices architecture
- ✅ You need advanced orchestration (service mesh, sidecars)
- ✅ Your team has Kubernetes expertise
- ✅ You need maximum control and customization
- ❌ Higher cost and complexity are acceptable

### Can I Change Later?

**Yes!** This template supports incremental adoption. See [Incremental Adoption Guide](docs/INCREMENTAL-ADOPTION.md).

- **Start simple:** Begin with Lambda
- **Add later:** Enable App Runner or EKS when needed
- **Mix and match:** Use Lambda + App Runner together
- **What never changes:** S3 state bucket, OIDC provider, IAM roles

---

## 📋 Prerequisites

**📚 For detailed installation instructions**, see [INSTALLATION.md](docs/INSTALLATION.md).

- **AWS Account** with administrative access
- **Terraform** >= 1.13.0
- **AWS CLI** configured (`aws configure`)
- **GitHub Repository** for your project
- **uv** (for Python development): `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **tflint** (for Terraform linting): See installation instructions below
- **Make** (optional, for convenience commands)

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  AWS Account                                                  │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ Bootstrap Infrastructure (One-Time Setup)              │   │
│  │                                                        │   │
│  │  • S3 State Bucket (versioned, encrypted)              │   │
│  │  • GitHub OIDC Provider                                │   │
│  │  • IAM Roles (dev, test, prod)                         │   │
│  │  • ECR Repositories                                    │   │
│  │  • EKS Cluster (if enabled)                            │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐   │
│  │ Application Infrastructure (Per Environment)           │   │
│  │                                                        │   │
│  │  ┌──────────────────────────────────────────────────┐  │   │
│  │  │ API Gateway (Standard Entry Point)               │  │   │
│  │  │  • Rate limiting & throttling                    │  │   │
│  │  │  • CloudWatch logging & X-Ray tracing            │  │   │
│  │  │  • CORS & security policies                      │  │   │
│  │  └──────────────────────┬───────────────────────────┘  │   │
│  │                         │                              │   │
│  │                         ↓                              │   │
│  │  • Lambda Functions (AWS_PROXY integration)            │   │
│  │  • App Runner Services (HTTP_PROXY integration)        │   │
│  │  • EKS Workloads (future support)                      │   │
│  │                                                        │   │
│  │  Note: Direct access URLs disabled in cloud            │   │
│  │        (enabled for local development only)            │   │
│  └────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

> **📖 First time?** This gets you running in ~15 minutes. For detailed explanations, see the [complete deployment guide](docs/TERRAFORM-BOOTSTRAP.md).

### 1. Clone and Setup

```bash
# Clone template
git clone git@github.com:gpazevedo/aws-base-python.git my-project
cd my-project
git remote remove origin

# Test Python setup
cd backend/api && uv sync && uv pip install pytest pytest-cov && cd ../..
make test
```

### 2. Configure Your Project

```bash
# Create config file
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars

# Edit bootstrap/terraform.tfvars with your values:
# - project_name: "my-project"
# - github_org: "my-org"
# - github_repo: "my-repo"
# - aws_region: "us-east-1"
# - enable_lambda: true (or enable_apprunner/enable_eks)
```

### 3. Deploy Bootstrap Infrastructure

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Deploy bootstrap (S3 state, OIDC, IAM roles, ECR)
make bootstrap-create
make bootstrap-init
make bootstrap-apply
```

### 4. Deploy Your Application

```bash
# Generate Terraform configs
make setup-terraform-backend
make setup-terraform-lambda     # Optional: generates example Lambda Terraform
make setup-terraform-apprunner  # Optional: generates example App Runner Terraform

# Build and push Docker image to ECR
./scripts/docker-push.sh dev api Dockerfile.lambda

# Deploy infrastructure
make app-init-dev
make app-apply-dev

# ============================================================================
# Test Your Deployment
# ============================================================================

# Get primary endpoint (API Gateway URL for cloud, Lambda URL for local)
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)
echo "Testing API at: $PRIMARY_URL"

# ----------------------------------------------------------------------------
# 1. Health Check Endpoints
# ----------------------------------------------------------------------------

echo "Testing health checks..."

# Comprehensive health check
curl -s $PRIMARY_URL/health | jq
# Expected: {"status":"healthy","timestamp":"...","uptime_seconds":...,"version":"0.1.0"}

# Liveness probe
curl -s $PRIMARY_URL/liveness | jq
# Expected: {"status":"alive"}

# Readiness probe
curl -s $PRIMARY_URL/readiness | jq
# Expected: {"status":"ready"}

# ----------------------------------------------------------------------------
# 2. Application Endpoints
# ----------------------------------------------------------------------------

echo "Testing application endpoints..."

# Root endpoint
curl -s $PRIMARY_URL/ | jq
# Expected: {"message":"Hello, World!","version":"0.1.0"}

# Greet with query parameter
curl -s "$PRIMARY_URL/greet?name=Alice" | jq
# Expected: {"message":"Hello, Alice!","version":"0.1.0"}

# Greet with default name
curl -s $PRIMARY_URL/greet | jq
# Expected: {"message":"Hello, World!","version":"0.1.0"}

# Greet with POST request
curl -s -X POST $PRIMARY_URL/greet \
  -H "Content-Type: application/json" \
  -d '{"name":"Bob"}' | jq
# Expected: {"message":"Hello, Bob!","version":"0.1.0"}

# ----------------------------------------------------------------------------
# 3. Error Handling
# ----------------------------------------------------------------------------

echo "Testing error handling..."

# Test error endpoint
curl -s $PRIMARY_URL/error | jq
# Expected: 500 error with {"detail":"This is a test error"}

# Test validation error (missing required field)
curl -s -X POST $PRIMARY_URL/greet \
  -H "Content-Type: application/json" \
  -d '{}' | jq
# Expected: 422 validation error

# ----------------------------------------------------------------------------
# 4. Interactive Documentation
# ----------------------------------------------------------------------------

echo "Opening interactive API documentation..."

# View Swagger UI (interactive API explorer)
open "$PRIMARY_URL/docs"  # macOS
# xdg-open "$PRIMARY_URL/docs"  # Linux

# View ReDoc (alternative documentation)
open "$PRIMARY_URL/redoc"  # macOS

# Download OpenAPI schema
curl -s $PRIMARY_URL/openapi.json > api-schema.json
echo "OpenAPI schema saved to api-schema.json"

# ----------------------------------------------------------------------------
# 5. API Key Authentication (if enabled)
# ----------------------------------------------------------------------------

# If you enabled API Key authentication (enable_api_key = true), get the key:
if cd terraform && terraform output api_key_value &>/dev/null; then
  echo "API Key authentication is enabled"
  API_KEY=$(cd terraform && terraform output -raw api_key_value)

  # Test with API Key
  echo "Testing with API Key..."
  curl -s -H "x-api-key: $API_KEY" $PRIMARY_URL/health | jq

  # Test without API Key (should fail)
  echo "Testing without API Key (should return 403)..."
  curl -s $PRIMARY_URL/health | jq
  # Expected: {"message":"Forbidden"}
fi

# ----------------------------------------------------------------------------
# 6. Complete Test Script (Optional)
# ----------------------------------------------------------------------------

# For comprehensive testing, create a test script:
cat > test-api.sh <<'EOF'
#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get API URL
cd terraform
PRIMARY_URL=$(terraform output -raw primary_endpoint)
API_KEY=$(terraform output -raw api_key_value 2>/dev/null || echo "")
cd ..

echo -e "${YELLOW}Testing API at: $PRIMARY_URL${NC}\n"

# Helper function to test endpoint
test_endpoint() {
  local method=$1
  local path=$2
  local expected_status=$3
  local data=$4
  local description=$5

  echo -n "Testing: $description... "

  # Build curl command
  local cmd="curl -s -w '%{http_code}' -o /tmp/response.json"
  if [ -n "$API_KEY" ]; then
    cmd="$cmd -H 'x-api-key: $API_KEY'"
  fi
  cmd="$cmd -X $method"
  if [ -n "$data" ]; then
    cmd="$cmd -H 'Content-Type: application/json' -d '$data'"
  fi
  cmd="$cmd $PRIMARY_URL$path"

  # Execute request
  status_code=$(eval $cmd)

  # Check status code
  if [ "$status_code" = "$expected_status" ]; then
    echo -e "${GREEN}✓ PASS${NC} (HTTP $status_code)"
    jq -C '.' /tmp/response.json 2>/dev/null || cat /tmp/response.json
  else
    echo -e "${RED}✗ FAIL${NC} (Expected $expected_status, got $status_code)"
    cat /tmp/response.json
    exit 1
  fi
  echo ""
}

# Run tests
echo -e "${YELLOW}Health Check Endpoints${NC}"
test_endpoint "GET" "/health" "200" "" "Health check"
test_endpoint "GET" "/liveness" "200" "" "Liveness probe"
test_endpoint "GET" "/readiness" "200" "" "Readiness probe"

echo -e "${YELLOW}Application Endpoints${NC}"
test_endpoint "GET" "/" "200" "" "Root endpoint"
test_endpoint "GET" "/greet" "200" "" "Greet with default name"
test_endpoint "GET" "/greet?name=Alice" "200" "" "Greet with query param"
test_endpoint "POST" "/greet" "200" '{"name":"Bob"}' "Greet with POST"

echo -e "${YELLOW}Error Handling${NC}"
test_endpoint "GET" "/error" "500" "" "Error endpoint"
test_endpoint "POST" "/greet" "422" '{}' "Validation error"

echo -e "\n${GREEN}All tests passed!${NC}"
EOF

chmod +x test-api.sh

# Run the test script
./test-api.sh
```

> 📖 **API Documentation:** See [API-ENDPOINTS.md](docs/API-ENDPOINTS.md) for all available endpoints including:
> - Health checks: `/health`, `/liveness`, `/readiness`
> - API endpoints: `/`, `/greet`, `/error`
> - Interactive docs: `/docs` (Swagger UI), `/redoc`, `/openapi.json`
>
> **Access Mode:**
> - **Cloud deployments (dev, test, prod)**: API Gateway URL (standard)
> - **Local development**: Lambda Function URL (when `enable_direct_access = true`)

### 5. Configure GitHub Actions (Optional)

For automated CI/CD, configure GitHub repository settings:

**Secrets** (Settings → Secrets and variables → Actions):
- `AWS_ACCOUNT_ID` - Your AWS account number
- `RELEASE_PLEASE_TOKEN` - Personal Access Token for automated releases (see below)

**Variables** (Settings → Secrets and variables → Actions):
- `AWS_REGION` - e.g., "us-east-1"
- `PROJECT_NAME` - Your project name
- `LAMBDAS` - e.g., ["api"] (for Lambda deployments)
- `APPRUNNER_SERVICES` - e.g., [] (for App Runner deployments)
- `EKS_SERVICES` - e.g., ["api"] (for EKS deployments)
- `EKS_CLUSTER_NAME` - e.g., "my-project-dev" (for EKS deployments)

**Environments** (Settings → Environments):
- Create "dev" environment with secret: `AWS_ROLE_ARN_DEV`
- Create "prod" environment with secret: `AWS_ROLE_ARN_PROD`

> Get ARN values: `aws iam list-roles --query 'Roles[?contains(RoleName, `github-actions`)].Arn'`

#### Setting up Release Please Token

The `RELEASE_PLEASE_TOKEN` is required for automated release management. GitHub's default `GITHUB_TOKEN` cannot create pull requests due to security restrictions.

**To create the token:**

1. Go to **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**
2. Click **Generate new token**
3. Configure:
   - **Name**: `Release Please Token`
   - **Expiration**: 90 days (recommended)
   - **Repository access**: Select this repository
   - **Permissions**:
     - **Contents**: Read and write
     - **Pull requests**: Read and write
4. Add the token as repository secret `RELEASE_PLEASE_TOKEN`

**📖 For detailed instructions**, see [Release Please Documentation](docs/RELEASE-PLEASE.md)

### 6. Setup Code Quality (Optional)

```bash
# Install pre-commit hooks (Ruff, Pyright, Terraform linting)
make setup-pre-commit

# Manual checks
make lint test typecheck
```

See [Pre-commit Documentation](docs/PRE-COMMIT.md) for details.

### 7. Push to GitHub

```bash
git add .
git commit -m "Initial setup"
git push origin main
```

**✅ Done!** Your infrastructure is deployed and CI/CD is ready.


---


## 🧪 Testing & Deployment

### Local Testing

Edit backend/api/pyproject.toml and change project name from my-project to your project name.

#### 1. Run Unit Tests

Configure in your IDE, "pytest" as your Test Framework.
Install pytest if necessary.

```bash
# Run unit tests
make test
```

#### 2. Test Python Backend Locally

```bash
cd backend/api

# Install dependencies
uv sync

# Run the Lambda handler locally
uv run python -c "
from main import handler
event = {'name': 'World'}
context = None
result = handler(event, context)
print(result)
"

# Or create a test script for easier testing
cat > test_local.py <<'EOF'
from main import handler

# Test Lambda handler
event = {'name': 'World'}
context = None
result = handler(event, context)
print("Lambda Response:", result)
EOF

uv run python test_local.py
```

#### 3. Test Lambda Container Locally (Docker)

```bash
# Set your project name (from bootstrap/terraform.tfvars)
export PROJECT_NAME="my-project"  # Replace with your actual project name

# Build Lambda container for arm64 (production, default)
make docker-build

# OR build for amd64 (local testing on x86_64 machines)
make docker-build-amd64
# Alternatively: make docker-build ARCH=amd64

# Run container locally (use appropriate architecture tag)
# For arm64 (default):
docker run -p 9000:8080 ${PROJECT_NAME}:arm64-latest
# For amd64 (local testing):
docker run -p 9000:8080 ${PROJECT_NAME}:amd64-latest

# Test in another terminal
curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"name": "World"}'
```

**Multi-Architecture Docker Support:**

All Dockerfiles support building for both arm64 and amd64 architectures:

- **arm64** (default): For production AWS services (Lambda Graviton2, App Runner, EKS on Graviton nodes)
- **amd64**: For local testing on Intel/AMD x86_64 machines

**How it works:**
- All Dockerfiles use `FROM --platform=$TARGETPLATFORM` with multi-arch base images
- `Dockerfile.lambda`: Uses `public.ecr.aws/lambda/python:3.13` (multi-arch manifest)
- `Dockerfile.apprunner` & `Dockerfile.eks`: Use `python:3.13-slim` (multi-arch manifest)
- Docker BuildKit automatically sets `TARGETPLATFORM` based on `--platform` flag
- **Both build AND runtime stages use TARGET platform** (deployment CPU)
- **Production deployments (`make docker-push-*`) ALWAYS build and push arm64 images**
- Images are tagged with architecture: `myapp:arm64-latest`, `myapp:amd64-latest`

**Why TARGETPLATFORM for both stages?**
- Python packages with C extensions (numpy, pillow, etc.) must be compiled for the TARGET architecture
- Unlike Go/Rust where builder can cross-compile, Python extensions need native compilation for target CPU
- See [Docker Multi-Architecture guide](docs/DOCKER-MULTIARCH.md) for detailed explanation

**⚠️ ARM64 Guarantee for ECR:**
**All images pushed to Amazon ECR are guaranteed to use arm64 architecture.** This is hardcoded in `docker-push.sh` and cannot be overridden. Local testing with other architectures is possible but these images are never pushed to ECR.

📖 **See [ARM64 Architecture Guarantee](docs/DOCKER-ARM64-GUARANTEE.md) for complete details on how this is enforced.**

### Deploy to AWS

#### ⚠️ IMPORTANT: Use GitHub Actions for All AWS Deployments

**All deployments to AWS must be done through GitHub Actions.** This ensures:
- ✅ Consistent arm64 builds (no emulation issues)
- ✅ Automated testing before deployment
- ✅ Audit trail of all changes
- ✅ No manual credential management
- ✅ Reproducible deployments

#### Recommended: CI/CD Deployment (GitHub Actions)

**Prerequisites:**

1. ✅ **Bootstrap infrastructure deployed** (`make bootstrap-apply`)
2. ✅ **Backend configs generated** (`make setup-terraform-backend`)
3. ✅ **Application Terraform files created** (`make setup-terraform-lambda` or `make setup-terraform-apprunner` - optional)
4. ✅ **GitHub repository secrets configured** (see bootstrap output)

**Deployment workflow:**

```bash
# 1. Write your code
vim backend/api/main.py

# 2. Test locally
cd backend/api && uv run python -c "from main import handler; print(handler({'name':'World'}, None))"

# 3. Commit and push
git add .
git commit -m "feat: Add Lambda handler"
git push origin main

# 4. GitHub Actions automatically:
#    - Runs tests
#    - Builds arm64 Docker image
#    - Pushes to ECR
#    - Deploys infrastructure with Terraform
#    - Runs smoke tests

# 5. Monitor deployment
# Visit: https://github.com/<your-org>/<your-repo>/actions
```

**Deploy to different environments:**
```bash
# Deploy to dev (automatic on push to main)
git push origin main

# Deploy to production (on release tag)
git tag v1.0.0
git push origin v1.0.0
```

#### Advanced: Manual Deployment (Not Recommended)

⚠️ **Warning:** Manual deployment is not recommended for the following reasons:
- Requires QEMU emulation for arm64 builds on x86_64 machines
- No automated testing before deployment
- Risk of credential exposure
- No deployment audit trail
- Potential for configuration drift

**Use GitHub Actions instead** (see above).

<details>
<summary>Click here for manual deployment instructions (advanced users only)</summary>

**Manual deployment workflow:**

```bash
# ============================================================================
# STEP 1: Build and Push Docker Image (Simplified - Recommended)
# ============================================================================
# One-step solution: Auto-detects architecture, installs QEMU if needed, builds and pushes
./scripts/docker-push.sh dev api Dockerfile.lambda

# This command automatically:
#   - Detects if you're on x86_64 or arm64
#   - Installs QEMU if needed (one-time setup)
#   - Builds for arm64 (AWS Graviton2)
#   - Pushes with hierarchical tags to ECR

# ============================================================================
# STEP 1 Alternative: Manual Build Steps (Advanced)
# ============================================================================
# If you prefer step-by-step control:

# 1a. Enable arm64 building (x86_64 machines only)
docker run --privileged --rm tonistiigi/binfmt --install all

# 1b. Build Docker image for arm64
make docker-build SERVICE=api

# 1c. Push image to ECR
make docker-push-dev

# Verify image was pushed successfully (hierarchical tags: api-dev-*)
aws ecr describe-images \
  --repository-name my-project \
  --query 'imageDetails[?imageTags[?contains(@, `api-dev`)]]'

# ============================================================================
# STEP 2: Deploy Infrastructure with Terraform
# ============================================================================
# Initialize Terraform (only needed once)
make app-init-dev

# Review what will be created
make app-plan-dev

# Deploy Lambda function and related AWS resources
make app-apply-dev

# ============================================================================
# STEP 3: Test
# ============================================================================
# Get Lambda Function URL
LAMBDA_URL=$(cd terraform && terraform output -raw lambda_function_url)

# Test the deployed Lambda
curl -X POST $LAMBDA_URL \
  -H "Content-Type: application/json" \
  -d '{"name": "World"}'
```

**Important:**
- You must have AWS credentials configured locally
- **⚠️ Docker image MUST exist in ECR before running `make app-apply-dev`**
  - The Lambda function will reference: `{ecr-repo}:api-dev-latest`
  - Build and push first: `make docker-build && make docker-push-dev`
  - Or deploy via GitHub Actions (recommended)
- Use GitHub Actions for production deployments

</details>

🔄 **For updates after initial deployment:**
```bash
# Update your code in backend/
# Then rebuild and push
make docker-build && make docker-push-dev

# Lambda will automatically use the new image
# (Terraform ignores image URI changes via lifecycle rule)

# If you need to force Lambda to pick up the new image:
aws lambda update-function-code \
  --function-name my-project-dev-api \
  --image-uri $(aws ecr describe-repositories \
    --repository-names my-project \
    --query 'repositories[0].repositoryUri' --output text):dev-latest
```

#### CI/CD Deployment (GitHub Actions)

**Trigger deployment:**

```bash
# Push to main branch (deploys to dev)
git add .
git commit -m "feat: Add Lambda handler"
git push origin main

# Create release v0.1.0 (deploys to prod)
git tag v0.1.0
git push origin v0.1.0
```

**Monitor deployment:**
- GitHub Actions: `https://github.com/<org>/<repo>/actions`
- AWS Lambda: `https://console.aws.amazon.com/lambda`
- CloudWatch Logs: `https://console.aws.amazon.com/cloudwatch`

#### Test Deployed API

```bash
# Get primary endpoint (API Gateway by default)
cd terraform
terraform output primary_endpoint

# Get deployment mode to see what's configured
terraform output deployment_mode

# Test the API Gateway endpoint
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl $PRIMARY_URL
curl $PRIMARY_URL/health
curl $PRIMARY_URL/docs

# View API Gateway configuration
terraform output api_gateway_url
terraform output api_gateway_id

# For local development with direct access
# (when enable_direct_access = true in environments/local.tfvars)
terraform output lambda_function_url
```

### Deployment Workflow Summary

#### Manual Deployment Flow

```
┌─────────────────────────────────────────────────────────────┐
│  PHASE 1: Bootstrap (One-time setup)                        │
│                                                             │
│  1. Configure: cp bootstrap/terraform.tfvars.example ...    │
│  2. Create S3: make bootstrap-create                        │
│  3. Initialize: make bootstrap-init                         │
│  4. Deploy: make bootstrap-apply                            │
│  5. Setup: make setup-terraform-backend                     │
│                                                             │
│  Creates: S3, ECR, IAM roles, OIDC provider                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 2: Development & Testing                             │
│                                                             │
│  1. Write code in backend/api/ or backend/worker/           │
│  2. Test locally: uv run python -c "from main..."           │
│  3. Run tests: make test                                    │
│  4. Test container: make docker-build-amd64                 │
│                    docker run -p 9000:8080 ...              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 3: Build & Push Docker Image (REQUIRED!)             │
│                                                             │
│  1. Build: make docker-build          (arm64 for AWS)       │
│  2. Push:  make docker-push-dev       (to ECR)              │
│  3. Verify: aws ecr describe-images --repository-name ...   │
│                                                             │
│  ⚠️  Image MUST exist in ECR before Terraform deploy!       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 4: Deploy Infrastructure                             │
│                                                             │
│  1. Generate: make setup-terraform-lambda or                │
│               make setup-terraform-apprunner (optional)     │
│  2. Init:     make app-init-dev                             │
│  3. Plan:     make app-plan-dev                             │
│  4. Deploy:   make app-apply-dev                            │
│                                                             │
│  Creates: Lambda function, CloudWatch Logs, Function URL    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  PHASE 5: Test Deployment                                   │
│                                                             │
│  1. Get URL: cd terraform && terraform output               │
│  2. Test: curl -X POST $LAMBDA_URL -d '{"name":"World"}'    │
│  3. Check logs: aws logs tail /aws/lambda/...               │
└─────────────────────────────────────────────────────────────┘
```

#### CI/CD Deployment Flow (GitHub Actions)

```
┌─────────────────────────────────────────────────────────────┐
│                     Local Development                       │
│                                                             │
│  1. Write code in backend/api/ or backend/worker/           │
│  2. Run tests: make test                                    │
│  3. Test locally: uv run python -c "from main..."           │
│  4. Test container: docker run -p 9000:8080                 │
│  5. Commit: git commit -m "feat: ..."                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   Push to GitHub                            │
│                                                             │
│  git push origin main                                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              GitHub Actions (Automatic)                     │
│                                                             │
│  1. Checkout code                                           │
│  2. Run tests (pytest)                                      │
│  3. Build Docker image (arm64, uv-based)                    │
│  4. Push to ECR                          ← Image created!   │
│  5. Deploy infrastructure (Terraform)    ← Uses image       │
│  6. Run smoke tests                                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  AWS (Production)                           │
│                                                             │
│  ✅ Lambda function updated                                 │
│  ✅ Available at API Gateway URL                            │
│  ✅ CloudWatch Logs enabled                                 │
│  ✅ X-Ray tracing active                                    │
└─────────────────────────────────────────────────────────────┘
```

### Next Steps

- **View logs**: Check CloudWatch Logs for function output
- **Monitor**: Set up CloudWatch dashboards and alarms

📖 **Learn more:**
- [Terraform Bootstrap Guide](docs/TERRAFORM-BOOTSTRAP.md) - Complete deployment walkthrough
- [Docker Multi-Architecture](docs/DOCKER-MULTIARCH.md) - arm64 vs amd64, BuildKit, cross-compilation
- [Incremental Adoption](docs/INCREMENTAL-ADOPTION.md) - Start with Lambda, add EKS later
- [Pre-commit Hooks](docs/PRE-COMMIT.md) - Automated code quality

---

## 📝 Configuration Examples

### Example 1: Simple Lambda API

```hcl
# bootstrap/terraform.tfvars
project_name = "my-api"
github_org   = "mycompany"
github_repo  = "my-api"

enable_lambda    = true
enable_apprunner = false
enable_eks       = false

lambda_use_container_image = true
ecr_repositories = []  # Single repository (recommended)
python_version = "3.13"
```

```hcl
# terraform/environments/dev.tfvars
# API Gateway configuration (standard mode)
enable_api_gateway_standard = true   # API Gateway entry point
enable_direct_access        = false  # Disable Lambda Function URLs

# Rate limiting for dev
api_throttle_burst_limit = 1000
api_throttle_rate_limit  = 500

# Logging
api_logging_level = "INFO"
enable_xray_tracing = true
```

**Result**: Lambda functions with API Gateway as standard entry point, rate limiting, and comprehensive logging

---

### Example 2: Containerized Web App (App Runner)

```hcl
project_name = "my-webapp"
github_org   = "mycompany"
github_repo  = "my-webapp"

enable_lambda    = false
enable_apprunner = true
enable_eks       = false

ecr_repositories = ["api", "web", "worker"]
python_version   = "3.13"
```

**Result**: App Runner service with ECR repositories

---

### Example 3: Microservices Platform (EKS)

```hcl
project_name = "platform"
github_org   = "mycompany"
github_repo  = "platform"

enable_lambda = false
enable_apprunner = false
enable_eks    = true

eks_cluster_version     = "1.31"
eks_node_instance_types = ["t3.medium"]
ecr_repositories        = ["auth", "api", "data-processor"]

create_vpc = true
vpc_availability_zones = 3
```

**Result**: Complete EKS cluster with VPC, ECR, and IAM roles

---

### Example 4: Hybrid (Lambda + App Runner)

```hcl
project_name = "hybrid-app"
github_org   = "mycompany"
github_repo  = "hybrid-app"

enable_lambda    = true
enable_apprunner = true
enable_eks       = false

ecr_repositories = ["web-frontend"]
lambda_use_container_image = true
python_version = "3.13"
```

**Result**: Both Lambda and App Runner infrastructure with API Gateway integration

---

### Example 5: Local Development (Direct Access)

```hcl
# terraform/environments/local.tfvars
# Local development configuration
enable_api_gateway_standard = false  # Skip API Gateway overhead
enable_direct_access        = true   # Enable Lambda Function URLs

# Open CORS for local testing
cors_allow_origins = ["*"]
cors_allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
```

```bash
# Deploy locally
terraform init -backend-config=environments/dev-backend.hcl
terraform plan -var-file="environments/local.tfvars"
terraform apply -var-file="environments/local.tfvars"
```

**Result**: Lambda with direct Function URL for fast local iteration without API Gateway

---

## 🏗️ Multi-Service Backend Structure

This project supports a **multi-service backend architecture** where each service (API, worker, etc.) is organized in its own directory under `backend/`.

### Directory Organization

```
backend/
├── api/                   # API service (default)
│   ├── main.py           # Lambda handler / app entry point
│   ├── pyproject.toml    # Dependencies for API service
│   └── ...
└── worker/               # Worker service (optional)
    ├── main.py           # Worker handler
    ├── pyproject.toml    # Dependencies for worker service
    └── ...
```

### Working with Services

Use the `SERVICE` variable with make commands to specify which service to build/deploy:

```bash
# Build API service (default)
make docker-build SERVICE=api

# Build worker service
make docker-build SERVICE=worker

# Push API to dev
make docker-push-dev SERVICE=api

# Push worker to dev
make docker-push-dev SERVICE=worker
```

### Image Naming Convention

Images are tagged with a hierarchical naming scheme that includes the service folder:

**Format:** `{service}-{env}-{datetime}-{sha}`

**Example for API service in dev:**
```
backend/api → my-project:api-dev-2025-11-18-16-25-abc1234
```

**Three tags are created per build:**

1. **Primary tag with timestamp:**
   - `api-dev-2025-11-18-16-25-abc1234` (unique, timestamped version)

2. **Service latest:**
   - `api-dev-latest` (latest build for API in dev)

3. **Environment latest:**
   - `dev-latest` (latest build for any service in dev)

**Benefits:**
- **Hierarchical organization:** Images are organized by folder structure
- **Service isolation:** Clear separation between API, worker, and other services
- **Timestamp tracking:** Know exactly when each image was built
- **Git traceability:** SHA allows tracking back to source code
- **Easy rollback:** Use `-latest` tags for quick rollbacks
- **Environment safety:** Environment prefix prevents deploying dev to prod

### Docker Build Arguments

When building multi-service containers, the `SERVICE_FOLDER` build argument is automatically set:

```bash
# Example build command (done automatically by scripts)
docker build \
  --build-arg SERVICE_FOLDER=backend/api \
  -f backend/api/Dockerfile.lambda \
  -t my-project:api-dev-latest \
  backend/api
```

### Adding a New Service

To add a new service (e.g., "scheduler"):

1. **Create directory structure:**
   ```bash
   mkdir -p backend/scheduler
   cp -r backend/api/* backend/scheduler/
   ```

2. **Customize the service:**
   ```bash
   cd backend/scheduler
   vim main.py  # Implement scheduler logic
   vim pyproject.toml  # Update dependencies
   ```

3. **Build and deploy:**
   ```bash
   make docker-build SERVICE=scheduler
   make docker-push-dev SERVICE=scheduler
   ```

4. **Images will be tagged as:**
   - `scheduler-dev-2025-11-18-16-25-abc1234`
   - `scheduler-dev-latest`
   - `dev-latest`

---

## 🐍 Python Development with uv

### Initialize Project

```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create new project
cp pyproject.toml.example pyproject.toml

# Initialize uv
uv init

# Install dependencies
uv sync

# Add a package
uv add fastapi uvicorn boto3

# Add dev dependencies
uv add --dev pytest black ruff
```

### Project Structure

```
backend/
├── api/                    # API service
│   ├── __init__.py
│   ├── main.py             # Application entry point
│   ├── test_main.py        # Test suite
│   ├── pyproject.toml      # Project configuration
│   └── uv.lock             # Locked dependencies (commit to git)
├── worker/                 # Worker service (example)
│   ├── __init__.py
│   ├── main.py
│   ├── test_main.py
│   ├── pyproject.toml
│   └── uv.lock
├── Dockerfile.lambda       # Lambda container (shared)
├── Dockerfile.apprunner    # App Runner container (shared)
└── Dockerfile.eks          # EKS container (shared)
```

### Build Containers

```bash
# Lambda (API service)
cd backend
docker build --build-arg SERVICE_FOLDER=api --platform=linux/arm64 \
  -f Dockerfile.lambda -t my-project:api-lambda .

# Lambda (Worker service)
docker build --build-arg SERVICE_FOLDER=worker --platform=linux/arm64 \
  -f Dockerfile.lambda -t my-project:worker-lambda .

# App Runner (API service)
docker build --build-arg SERVICE_FOLDER=api --platform=linux/arm64 \
  -f Dockerfile.apprunner -t my-project:api-apprunner .

# EKS (API service)
docker build --build-arg SERVICE_FOLDER=api --platform=linux/arm64 \
  -f Dockerfile.eks -t my-project:api-eks .
```

---

## 🔧 Make Commands

### Bootstrap
```bash
make bootstrap-init      # Initialize Terraform
make bootstrap-plan      # Plan changes
make bootstrap-apply     # Apply infrastructure
make bootstrap-output    # Show outputs
make bootstrap-destroy   # Destroy (DANGER!)
```

### Setup
```bash
make setup-terraform-backend      # Generate backend configs
```

### Application
```bash
make app-init-dev       # Initialize dev environment
make app-plan-dev       # Plan dev changes
make app-apply-dev      # Deploy to dev
```

### Docker
```bash
# Build Docker images (SERVICE=api by default)
make docker-build                              # Build api service, arm64 (default)
make docker-build-amd64                        # Build api service, amd64 (local testing)
make docker-build SERVICE=worker               # Build worker service, arm64
make docker-build SERVICE=worker ARCH=amd64    # Build worker service, amd64
make docker-build DOCKERFILE=Dockerfile.eks    # Build with EKS Dockerfile

# Push to ECR (always builds and pushes arm64)
make docker-push-dev                           # Push api service to dev ECR
make docker-push-dev SERVICE=worker            # Push worker service to dev ECR
make docker-push-test SERVICE=api              # Push api service to test ECR
make docker-push-prod SERVICE=worker           # Push worker service to prod ECR

# Direct script usage (alternative)
./scripts/docker-push.sh dev api Dockerfile.lambda      # Push api to dev
./scripts/docker-push.sh prod worker Dockerfile.lambda  # Push worker to prod
```

---

## 📁 Directory Structure

```
aws-base/
├── bootstrap/                  # Bootstrap infrastructure (foundational)
│   ├── main.tf                # Core resources (S3, OIDC, IAM)
│   ├── lambda.tf              # Lambda execution roles (conditional)
│   ├── apprunner.tf           # App Runner roles (conditional)
│   ├── eks.tf                 # EKS cluster (conditional)
│   ├── ecr.tf                 # ECR repositories (conditional)
│   ├── networking.tf          # VPC resources (conditional)
│   ├── variables.tf           # All configuration options
│   ├── outputs.tf             # Bootstrap outputs
│   ├── terraform.tfvars       # Your configuration (gitignored)
│   └── terraform.tfvars.example
│
├── terraform/                 # Application infrastructure (see INCREMENTAL-ADOPTION.md)
│   ├── backend.tf             # S3 backend configuration
│   ├── main.tf                # Provider and resources
│   ├── environments/
│   │   ├── dev.tfvars
│   │   ├── dev-backend.hcl    # Generated by setup script
│   │   ├── test.tfvars
│   │   └── prod.tfvars
│   └── resources/             # Application-specific resources
│       ├── dynamodb.tf        # DynamoDB tables
│       ├── lambda-functions.tf # Lambda functions
│       ├── api-gateway.tf     # API Gateway
│       └── ...                # Other resources
│
├── backend/                   # Python backend application (multi-service)
│   ├── api/                   # API service
│   │   ├── __init__.py
│   │   ├── main.py            # Lambda handler / application entry point
│   │   ├── test_main.py       # Test suite
│   │   ├── pyproject.toml     # Python dependencies + config
│   │   └── uv.lock            # Locked dependencies
│   ├── worker/                # Worker service (optional)
│   │   ├── __init__.py
│   │   ├── main.py            # Worker handler
│   │   ├── test_main.py       # Test suite
│   │   ├── pyproject.toml     # Python dependencies + config
│   │   └── uv.lock            # Locked dependencies
│   ├── Dockerfile.lambda      # Shared Lambda container (uses SERVICE_FOLDER arg)
│   ├── Dockerfile.apprunner   # Shared App Runner container
│   └── Dockerfile.eks         # Shared EKS container
│
├── scripts/
│   ├── setup-terraform-backend.sh    # Generate backend configs
│   ├── setup-terraform-lambda.sh     # Generate Lambda Terraform files
│   ├── setup-terraform-apprunner.sh  # Generate App Runner Terraform files
│   ├── generate-workflows.sh         # Generate GitHub Actions workflows
│   ├── docker-push.sh                # Build and push Docker images to ECR
│   ├── sync-tfvars-to-env.py         # Sync terraform vars to .env
│   └── setup-pre-commit.sh         # Setup pre-commit hooks
│
├── docs/
│   ├── INCREMENTAL-ADOPTION.md     # Guidance on infrastructure placement
│   ├── TERRAFORM-BOOTSTRAP.md      # Bootstrap deep dive
│   ├── INSTALLATION.md             # Tool installation guide
│   ├── DOCKER-MULTIARCH.md         # Multi-architecture Docker builds
│   ├── PRE-COMMIT.md               # Code quality setup
│   └── SCRIPTS.md                  # Scripts documentation
│
├── .pre-commit-config.yaml    # Pre-commit hooks config
├── Makefile                   # Convenience commands
└── README.md                  # This file
```

---

## 🔐 Security Best Practices

### Implemented
- ✅ S3 bucket encryption (AES256)
- ✅ S3 versioning enabled
- ✅ S3 public access blocked
- ✅ GitHub OIDC (no long-lived credentials)
- ✅ IAM least-privilege policies
- ✅ ECR vulnerability scanning
- ✅ VPC private subnets
- ✅ Security groups with minimal access

### Recommendations
- 🔒 Enable `prevent_destroy` on state bucket after first apply
- 🔒 Use AWS Secrets Manager for sensitive configuration
- 🔒 Enable CloudTrail for audit logging
- 🔒 Set up AWS Config for compliance
- 🔒 Enable GuardDuty for threat detection
- 🔒 Review IAM policies regularly

---

## 🎯 Use Cases

### Lambda (Serverless Functions)
**Best for:**
- REST APIs (API Gateway + Lambda)
- Background jobs and event processing
- Scheduled tasks (EventBridge + Lambda)
- Image/video processing
- Data transformation

**Limitations:**
- 15-minute execution limit
- 10GB memory limit
- Cold start latency

---

### App Runner (Containerized Web Apps)
**Best for:**
- Web applications and APIs
- Microservices
- Simple containerized workloads
- Auto-scaling web services

**Advantages:**
- No infrastructure management
- Built-in HTTPS
- Auto-scaling
- Simple deployment

**Limitations:**
- Regional service (not all regions)
- Less control than EKS

---

### EKS (Kubernetes)
**Best for:**
- Complex microservices
- Multi-container applications
- Existing Kubernetes expertise
- Advanced networking requirements
- Stateful applications

**Considerations:**
- Higher complexity
- More expensive
- Requires Kubernetes knowledge

---

## 📊 Cost Estimates

### Lambda
- **Compute**: $0.0000166667 per GB-second (arm64)
- **Requests**: $0.20 per 1M requests
- **Free tier**: 1M requests/month, 400,000 GB-seconds/month
- **Typical cost**: $5-50/month for small apps

### App Runner
- **Compute**: $0.064/vCPU-hour + $0.007/GB-hour
- **Build**: $0.005/build minute
- **Data transfer**: $0.09/GB out
- **Typical cost**: $20-100/month (1 vCPU, 2GB)

### EKS
- **Control plane**: $0.10/hour ($73/month)
- **Nodes**: EC2 pricing (t3.medium: ~$30/month each)
- **NAT Gateway**: $0.045/hour per AZ ($32/month each)
- **Typical cost**: $150-500/month (small cluster)

### Shared Costs
- **S3 state bucket**: $0.023/GB-month (negligible)
- **ECR storage**: $0.10/GB-month
- **ECR data transfer**: Free to Lambda/ECS/App Runner in same region

---

## 🆘 Troubleshooting

### Bootstrap fails with "bucket already exists"
**Solution**: The S3 bucket name must be globally unique. Change `state_bucket_name` in `terraform.tfvars`.

### Cannot assume GitHub Actions role
**Solution**:
1. Verify GitHub environment names match Terraform (dev, test, production)
2. Check repository name matches `github_repo` variable
3. Ensure OIDC provider thumbprint is current

### No endpoint available after deployment
**Solution**:
1. Check deployment mode: `terraform output deployment_mode`
2. Ensure either `enable_api_gateway_standard = true` OR `enable_direct_access = true` in your tfvars
3. API Gateway is the default for cloud deployments (dev, test, prod)
4. Direct access is for local development only

### API Gateway returns 403 Forbidden
**Solution**:
1. Check Lambda permissions: `aws_lambda_permission.api_gateway` must exist
2. Verify API Gateway deployment: `terraform output api_gateway_id`
3. Check IAM roles have `api_gateway_management` policy attached
4. Review CloudWatch logs: `terraform output cloudwatch_log_group_api_gateway`

### API Gateway rate limiting too restrictive
**Solution**:
1. Adjust throttling in your tfvars file:
   ```hcl
   api_throttle_burst_limit = 5000  # Increase as needed
   api_throttle_rate_limit  = 10000 # Requests per second
   ```
2. Check CloudWatch metrics for throttled requests
3. Monitor `4XXError` and `5XXError` metrics in API Gateway console

### API Gateway logs not appearing in CloudWatch
**Solution**:
1. Verify logging is enabled: Check `api_logging_level` in tfvars (should be "INFO" or "ERROR")
2. Check log group exists: `terraform output cloudwatch_log_group_api_gateway`
3. Ensure IAM role has CloudWatch Logs permissions
4. Wait 1-2 minutes for logs to appear after first request

### Lambda function works but API Gateway fails
**Solution**:
1. Test Lambda directly: `aws lambda invoke --function-name <name> output.json`
2. Check API Gateway integration: Integration type should be `AWS_PROXY`
3. Verify Lambda response format matches API Gateway requirements (statusCode, body, headers)
4. Review X-Ray traces if enabled: `enable_xray_tracing = true`

### EKS nodes not joining cluster
**Solution**:
1. Check security group allows node-to-control-plane communication
2. Verify IAM roles have correct policies attached
3. Check VPC has internet access (NAT gateway for private subnets)

### Lambda container image too large
**Solution**:
1. Use multi-stage Docker builds
2. Remove unnecessary dependencies from `pyproject.toml`
3. Consider Lambda layers for shared dependencies
4. Use `--no-cache` in `uv sync`

**For more details on API Gateway configuration**, see [terraform/README.md](terraform/README.md)

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📄 License

MIT License - see LICENSE file for details

---

## 🙏 Acknowledgments

- Built with [Terraform](https://www.terraform.io/)
- Python dependency management by [uv](https://github.com/astral-sh/uv)
- Inspired by AWS best practices and community contributions

---

## 📚 Documentation

### Project Documentation

This repository includes comprehensive documentation for all aspects of the bootstrap and development workflow:

#### 🏗️ Infrastructure & Deployment

- **[📖 Terraform Bootstrap Guide](docs/TERRAFORM-BOOTSTRAP.md)** - Complete guide to the bootstrap infrastructure
  - What resources are created and why
  - Configuration examples for all use cases
  - Step-by-step deployment instructions
  - State management strategy
  - Security best practices
  - Cost breakdown and estimates
  - Troubleshooting guide

- **[📈 Incremental Adoption](docs/INCREMENTAL-ADOPTION.md)** - How to start small and scale
  - Start with Lambda, add EKS later
  - Phase-by-phase migration guides
  - Cost evolution across phases
  - Decision matrices for choosing compute options
  - Safety guarantees (what never changes)

#### 🛠️ Development Tools

- **[🌐 API Endpoints](docs/API-ENDPOINTS.md)** - Complete API documentation
  - All available endpoints (health checks, API, docs)
  - Request/response examples
  - How to access via Lambda Function URL or API Gateway
  - Local development and testing instructions
  - Interactive documentation (Swagger UI, ReDoc)

- **[🔧 API Gateway Troubleshooting](docs/TROUBLESHOOTING-API-GATEWAY.md)** - Fix integration issues
  - Modular API Gateway architecture explained
  - Common issues and solutions
  - Migration guide from simplified to modular setup
  - Testing and debugging tips
  - API Key authentication troubleshooting

- **[🐳 ARM64 Architecture Guarantee](docs/DOCKER-ARM64-GUARANTEE.md)** - ECR image architecture enforcement
  - Why all ECR images must be arm64
  - How arm64 is enforced at multiple levels
  - Local testing with other architectures
  - Cost savings from Graviton2 processors
  - Migration guide from x86_64

- **[✅ Pre-commit Hooks](docs/PRE-COMMIT.md)** - Automated code quality
  - Ruff (linting + formatting) setup
  - Pyright (type checking) configuration
  - Installation and usage guide
  - Rule explanations
  - Troubleshooting

- **[⚙️ Scripts Documentation](docs/SCRIPTS.md)** - Automation scripts
  - `setup-terraform-backend.sh` - Generate backend configs
  - `setup-terraform-lambda.sh` - Generate example Lambda Terraform files
  - `setup-terraform-apprunner.sh` - Generate example App Runner Terraform files
  - `generate-workflows.sh` - Create GitHub Actions workflows
  - `docker-push.sh` - Build and push Docker images
  - `setup-pre-commit.sh` - Install code quality hooks

- **[🚀 Release Please](docs/RELEASE-PLEASE.md)** - Automated release management
  - Automatic version bumping and CHANGELOG generation
  - Conventional Commits specification
  - Release workflow and best practices
  - Configuration and troubleshooting

#### 📋 Quick Reference

| Document | Purpose | When to Read |
|----------|---------|--------------|
| [README.md](README.md) | Overview and quick start | **Start here** |
| [API-ENDPOINTS.md](docs/API-ENDPOINTS.md) | API documentation | After deployment, for API usage |
| [TROUBLESHOOTING-API-GATEWAY.md](docs/TROUBLESHOOTING-API-GATEWAY.md) | Fix API Gateway issues | When endpoints don't work or migrating setup |
| [DOCKER-ARM64-GUARANTEE.md](docs/DOCKER-ARM64-GUARANTEE.md) | ARM64 architecture enforcement | Understanding ECR image architecture |
| [TERRAFORM-BOOTSTRAP.md](docs/TERRAFORM-BOOTSTRAP.md) | Infrastructure deep dive | Before deploying bootstrap |
| [INCREMENTAL-ADOPTION.md](docs/INCREMENTAL-ADOPTION.md) | Scaling strategy | Planning architecture evolution |
| [PRE-COMMIT.md](docs/PRE-COMMIT.md) | Code quality setup | Setting up development environment |
| [SCRIPTS.md](docs/SCRIPTS.md) | Automation reference | Using helper scripts |
| [RELEASE-PLEASE.md](docs/RELEASE-PLEASE.md) | Release automation | Setting up releases and versioning |

### External Resources

- [FastAPI Documentation](https://fastapi.tiangolo.com/) - Modern web framework for APIs
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [App Runner Documentation](https://docs.aws.amazon.com/apprunner/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [uv Documentation](https://docs.astral.sh/uv/)
- [Ruff Documentation](https://docs.astral.sh/ruff/)
- [Pyright Documentation](https://microsoft.github.io/pyright/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## 📞 Support

For issues and questions:
- 🐛 [Open an Issue](https://github.com/your-org/your-repo/issues)
- 💬 [Discussions](https://github.com/your-org/your-repo/discussions)
- 📖 [Documentation](https://github.com/your-org/your-repo/wiki)

---

**Built with ❤️ for the AWS + Python community**
