# Scripts Documentation

## Overview

This project includes several automation scripts to streamline development and deployment workflows.

---

## 📜 Available Scripts

### 1. `setup-pre-commit.sh`

**Purpose**: Install and configure pre-commit hooks for automated code quality.

**Location**: `scripts/setup-pre-commit.sh`

**Usage**:
```bash
./scripts/setup-pre-commit.sh
# or
make setup-pre-commit
```

**What it does**:
1. Creates `pyproject.toml` from example if not exists
2. Installs Python dependencies with uv (Ruff, Pyright, pre-commit)
3. Installs pre-commit git hooks
4. Runs initial check on all files

**When to run**:
- Initial project setup
- After cloning the repository
- After updating `.pre-commit-config.yaml`

**See**: [docs/PRE-COMMIT.md](PRE-COMMIT.md) for complete documentation.

---

### 2. `setup-terraform-backend.sh`

**Purpose**: Auto-generates Terraform backend configuration files for application infrastructure.

**Location**: `scripts/setup-terraform-backend.sh`

**Usage**:
```bash
./scripts/setup-terraform-backend.sh
# or
make setup-terraform-backend
```

**What it does**:
1. Reads bootstrap outputs (`terraform_state_bucket`, `aws_region`)
2. Generates backend config files for each environment:
   - `terraform/environments/dev-backend.hcl`
   - `terraform/environments/test-backend.hcl`
   - `terraform/environments/prod-backend.hcl`

**Generated file example**:
```hcl
# terraform/environments/dev-backend.hcl
bucket       = "<YOUR-PROJECT>-terraform-state-123456789012"
key          = "environments/dev/terraform.tfstate"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
```

**When to run**:
- After initial bootstrap deployment
- After changing AWS region
- After recreating S3 state bucket

---

### 3. `setup-terraform-base.sh`

**Purpose**: Creates foundational Terraform configuration shared across all services.

**Location**: `scripts/setup-terraform-base.sh`

**Usage**:
```bash
./scripts/setup-terraform-base.sh
# or
make setup-terraform-base
```

**What it does**:
1. Reads project configuration from `bootstrap/terraform.tfvars` (if available)
2. Creates `terraform/` directory structure
3. Generates base Terraform files needed by all services:
   - `terraform/main.tf` - Provider and backend configuration
   - `terraform/variables.tf` - Common variable definitions
   - `terraform/outputs.tf` - Output values
   - `terraform/api-gateway.tf` - API Gateway common definitions
   - `terraform/README.md` - Documentation
4. Creates environment-specific variable files:
   - `terraform/environments/dev.tfvars`
   - `terraform/environments/test.tfvars`
   - `terraform/environments/prod.tfvars`

**When to run**:
- **Once** after completing bootstrap setup
- Before adding your first Lambda or AppRunner service
- When starting a new project

**Example workflow**:
```bash
# 1. Run bootstrap first
make bootstrap-apply

# 2. Generate backend configuration
make setup-terraform-backend

# 3. Create base Terraform files (run this once)
./scripts/setup-terraform-base.sh

# 4. Now add services with setup-terraform-lambda.sh or setup-terraform-apprunner.sh
```

---

### 4. `setup-terraform-lambda.sh`

**Purpose**: Generates Terraform configuration for individual Lambda services.

**Location**: `scripts/setup-terraform-lambda.sh`

**Prerequisites**:
- ✅ Base Terraform files created (run `setup-terraform-base.sh` first)
- ✅ Service directory exists in `backend/<service-name>/`

**Usage**:
```bash
# Syntax: ./scripts/setup-terraform-lambda.sh [SERVICE_NAME] [ENABLE_API_KEY]

# Create Lambda configuration for 'api' service (with API key disabled)
./scripts/setup-terraform-lambda.sh api false

# Create Lambda configuration for 'worker' service (with API key enabled)
./scripts/setup-terraform-lambda.sh worker true

# Default (creates 'api' service with API key enabled)
./scripts/setup-terraform-lambda.sh
```

**What it does**:
1. Validates that `backend/<service-name>/` directory exists
2. Creates `terraform/lambda-variables.tf` (if first Lambda service)
3. Generates `terraform/lambda-<service>.tf` with Lambda function definition
4. Appends API Gateway integration to `terraform/api-gateway.tf` (if it exists)
5. Sets up path-based routing for the service

**Generated infrastructure per service**:
- Lambda function using container images from ECR
- CloudWatch Logs with JSON formatting and retention policies
- IAM execution role
- API Gateway integration with path routing (`/<service>/*`)
- Environment-specific memory/timeout configurations
- Lifecycle rules for CI/CD compatibility

**Example workflow for adding a new Lambda service**:
```bash
# 1. Create service directory and code
mkdir -p backend/worker
cp backend/api/main.py backend/worker/main.py
cp backend/api/pyproject.toml backend/worker/pyproject.toml
# Edit worker/main.py for your service logic

# 2. Generate Terraform configuration
./scripts/setup-terraform-lambda.sh worker false

# 3. Build and push Docker image
./scripts/docker-push.sh dev worker Dockerfile.lambda

# 4. Deploy
make app-apply-dev
```

**API Gateway Path Routing**:
- First Lambda service (usually `api`) gets root path: `/`, `/*`
- Additional services get prefixed paths: `/<service>/*`
  - Example: `worker` → `/worker/health`, `/worker/jobs`

---

### 5. `setup-terraform-apprunner.sh`

**Purpose**: Generates Terraform configuration for individual AppRunner services.

**Location**: `scripts/setup-terraform-apprunner.sh`

**Prerequisites**:
- ✅ Base Terraform files created (run `setup-terraform-base.sh` first)
- ✅ Service directory exists in `backend/<service-name>/`

**Usage**:
```bash
# Syntax: ./scripts/setup-terraform-apprunner.sh [SERVICE_NAME]

# Create AppRunner configuration for 'web' service
./scripts/setup-terraform-apprunner.sh web

# Create AppRunner configuration for 'admin' service
./scripts/setup-terraform-apprunner.sh admin

# Default (creates 'runner' service)
./scripts/setup-terraform-apprunner.sh
```

**What it does**:
1. Validates that `backend/<service-name>/` directory exists
2. Creates `terraform/apprunner-variables.tf` (if first AppRunner service)
3. Generates `terraform/apprunner-<service>.tf` with AppRunner service definition
4. Optionally appends API Gateway integration to `terraform/api-gateway.tf`
5. Sets up auto-scaling and health check configuration

**Script prompts**:
```
Do you want to integrate this AppRunner service with API Gateway?
This will make the service accessible via API Gateway at /<service>/*
(y/N):
```

**Generated infrastructure per service**:
- AppRunner service using container images from ECR
- Auto-scaling configuration (min/max instances, concurrency)
- Health check configuration (path, interval, timeout)
- CloudWatch Logs integration via IAM instance role
- Optional API Gateway integration with HTTP_PROXY
- Lifecycle rules for CI/CD compatibility

**Example workflow for adding a new AppRunner service**:
```bash
# 1. Create service directory and code
mkdir -p backend/web
cp backend/runner/main.py backend/web/main.py
cp backend/runner/pyproject.toml backend/web/pyproject.toml
# Edit web/main.py for your service logic

# 2. Generate Terraform configuration
./scripts/setup-terraform-apprunner.sh web
# Answer 'y' to integrate with API Gateway

# 3. Build and push Docker image
./scripts/docker-push.sh dev web Dockerfile.apprunner

# 4. Deploy (takes 3-5 minutes for AppRunner)
make app-apply-dev
```

**API Gateway Integration**:
- Choose 'y': Service accessible via API Gateway at `/<service>/*`
- Choose 'N': Direct AppRunner URL only (e.g., `https://abc123.us-east-1.awsapprunner.com`)

**AppRunner vs Lambda**:

Use **AppRunner** when:
- ✅ Long-running web applications
- ✅ WebSocket or streaming support needed
- ✅ Want consistent performance (minimal cold starts)
- ✅ Need full control over web server

Use **Lambda** when:
- ✅ Event-driven workloads
- ✅ Sporadic traffic patterns
- ✅ Simple request/response APIs
- ✅ Need massive auto-scaling

---

### 6. `docker-push.sh`

**Purpose**: Build and push Docker images to Amazon ECR with proper tagging.

**Location**: `scripts/docker-push.sh`

**Usage**:
```bash
# Push to dev environment (default: Dockerfile.lambda)
./scripts/docker-push.sh dev

# Push to prod with specific repository name
./scripts/docker-push.sh prod api Dockerfile.apprunner

# Using make
make docker-push-dev
make docker-push-test
make docker-push-prod
```

**Arguments**:
1. **Environment** (required): `dev`, `test`, or `prod`
2. **Repository name** (optional): ECR repository name (defaults to project name)
3. **Dockerfile** (optional): Path to Dockerfile (defaults to `Dockerfile.lambda`)

**What it does**:
1. Reads bootstrap outputs (project name, AWS account, region)
2. Detects service folder from Dockerfile path (e.g., `backend/api`)
3. Authenticates to Amazon ECR
4. Builds Docker image with `--build-arg SERVICE_FOLDER` parameter
5. Creates multiple hierarchical tags:
   - `{service}-{env}-{datetime}-{sha}` - Unique build tag with timestamp
   - `{service}-{env}-latest` - Latest for this service
   - `{folder}/{env}/latest` - Latest for environment
6. Pushes all tags to ECR

**Features**:
- ✅ Auto-detects project configuration from bootstrap
- ✅ **Hierarchical image tagging** organized by folder structure
- ✅ **Timestamp-based versioning** for precise version tracking
- ✅ Multi-tag support for rollback capabilities
- ✅ Color-coded output for better visibility
- ✅ Validates AWS credentials and Dockerfile existence
- ✅ Git SHA tagging for traceability
- ✅ **Multi-service support** via SERVICE_FOLDER build argument

**New Image Tagging Format:**

The script now uses a hierarchical tagging scheme:

**Format:** `{folder}/{environment}/{service}-{datetime}-{git-sha}`

**Example for backend/api service in dev:**
```
api-dev-2025-11-18-16-25-abc1234  # Primary: folder/env/service-datetime-sha
api-dev-latest                    # Service latest
dev-latest                        # Environment latest
```

**Example output**:
```
🐳 Docker Push Script
   Environment: dev
   Service Folder: backend/api
   Dockerfile: backend/api/Dockerfile.lambda

✅ Configuration:
   Project: my-api
   Repository: my-api
   ECR URL: 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api
   AWS Account: 123456789012
   AWS Region: us-east-1
   Service: api

🔐 Logging into Amazon ECR...
✅ Successfully logged into ECR

🏗️  Building Docker image with SERVICE_FOLDER=backend/api...
✅ Docker image built successfully

📤 Pushing images to ECR with hierarchical tags...
✅ Successfully pushed images to ECR!

📋 Image URIs:
   123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api:api-dev-2025-11-18-16-25-abc1234
   123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api:api-dev-latest
   123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api:dev-latest
```

---


**What it does**:
1. Reads bootstrap outputs to detect enabled features:
   - Lambda enabled?
   - App Runner enabled?
   - EKS enabled?
   - Test environment enabled?
2. Reads IAM role ARNs for each environment (dev, test, prod)
3. **Detects ECR repository configuration:**
   - Uses single repository (when `ecr_repositories = []`)
   - Applies hierarchical tagging based on service folder structure
   - For legacy setups: looks for repos with "lambda" or "eks" in name

**Workflow features**:
- ✅ Uses OIDC for AWS authentication (no long-lived credentials)
- ✅ Builds and pushes Docker images to ECR
- ✅ Deploys to appropriate service (Lambda/App Runner/EKS)
- ✅ Environment-specific (dev, test, production)
- ✅ **Hierarchical image tagging strategy:**
  - Primary tag: `{service}-{env}-{datetime}-{git-sha}` (e.g., `api-dev-2025-11-18-16-25-abc1234`)
  - Service latest: `{service}-{env}-latest` (e.g., `api-dev-latest`)
  - Environment latest: `{folder}/{env}/latest` (e.g., `dev-latest`)
- ✅ Single ECR repository with hierarchical tags (recommended)
- ✅ Multi-service support via SERVICE_FOLDER build argument
- ✅ Timestamp-based versioning for precise tracking
- ✅ arm64 architecture by default (AWS Graviton2)

**Example: Lambda Dev Workflow**
```yaml
name: Deploy Lambda - Dev

on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'pyproject.toml'
      - 'Dockerfile.lambda'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/<YOUR-PROJECT>-github-actions-dev
          aws-region: us-east-1

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push Docker image
        env:
          SERVICE_FOLDER: backend/api
          TIMESTAMP: $(date +%Y-%m-%d-%H-%M)
        run: |
          docker build \
            --build-arg SERVICE_FOLDER=$SERVICE_FOLDER \
            -f $SERVICE_FOLDER/Dockerfile.lambda \
            -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG \
            $SERVICE_FOLDER
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      - name: Update Lambda function
        run: |
          aws lambda update-function-code \
            --function-name <YOUR-PROJECT>-dev-api \
            --image-uri $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
```

**When to run**:
- After initial bootstrap deployment
- After enabling/disabling compute options
- After adding new environments
- After changing ECR repository configuration
- **After adding new services to backend/**

**ECR Repository Detection**:

The script automatically detects your ECR configuration:

| ECR Configuration | Tagging Strategy |
|-------------------|------------------|
| `ecr_repositories = []` (recommended) | Single repo with hierarchical tags (`api-dev-latest`) |
| `ecr_repositories = ["lambda", "eks"]` (legacy) | Separate repos with flat tags (`dev-api-latest`) |

**Modern approach (single repository):**
```hcl
# bootstrap/terraform.tfvars
ecr_repositories = []  # Recommended
```

All services use single repository with hierarchical tags:
- Repository: `123456789.dkr.ecr.us-east-1.amazonaws.com/<YOUR-PROJECT>`
- Tags: `api-dev-2025-11-18-16-25-abc1234`, `worker-dev-latest`, etc.

**Image Tagging in Generated Workflows**:

All generated workflows create three hierarchical tags per build:
```bash
# Example for backend/api service, commit abc1234, environment "dev", built on 2025-11-18 at 16:25
api-dev-2025-11-18-16-25-abc1234  # Primary: folder/env/service-datetime-gitsha[0:7]
api-dev-latest                    # Latest for API service in dev
dev-latest                        # Latest for any service in dev
```

Benefits:
- **Hierarchical organization:** Images grouped by folder/environment/service
- **Timestamp precision:** Exact build time for debugging and auditing
- **Easy rollback:** Use `api-dev-latest` to rollback to last known good
- **Version tracking:** Git SHA in tag allows tracing to source code
- **Environment safety:** Environment prefix prevents deploying dev to prod
- **Multi-service support:** Clear separation between api, worker, and other services

**Customization**:
After generation, you can customize:
- Trigger conditions (branches, paths)
- Build arguments and Dockerfile locations
- Deployment strategies (blue/green, canary)
- Environment variables and secrets
- Health checks and rollback conditions
- **Service folders**: Change `SERVICE_FOLDER` variable in workflow

**Example: Custom service**
```yaml
# In generated workflow, change:
env:
  SERVICE_FOLDER: backend/api     # Default
# To:
env:
  SERVICE_FOLDER: backend/worker  # Custom

# Results in tags like: worker-dev-2025-11-18-16-25-abc1234
```

---

### Multi-Service Support

The scripts now support building and deploying multiple services from a single repository.

#### How It Works

**Directory Structure:**
```
backend/
├── api/                   # API service
│   ├── main.py
│   ├── pyproject.toml
│   └── Dockerfile.lambda
└── worker/               # Worker service
    ├── main.py
    ├── pyproject.toml
    └── Dockerfile.lambda
```

**SERVICE_FOLDER Parameter:**

All build scripts and workflows use the `SERVICE_FOLDER` build argument to:
1. Identify which service to build
2. Set the correct build context
3. Generate hierarchical image tags

**Example Docker Build:**
```bash
# Build API service
docker build \
  --build-arg SERVICE_FOLDER=backend/api \
  -f backend/api/Dockerfile.lambda \
  -t <YOUR-PROJECT>:api-dev-latest \
  backend/api

# Build worker service
docker build \
  --build-arg SERVICE_FOLDER=backend/worker \
  -f backend/worker/Dockerfile.lambda \
  -t <YOUR-PROJECT>:worker-dev-latest \
  backend/worker
```

**Image Tag Hierarchy in Single ECR Repository:**

All services share one ECR repository but are organized hierarchically:

```
<YOUR-PROJECT>/  (single ECR repository)
├── api-dev-2025-11-18-16-25-abc1234
├── api-dev-latest
├── worker-dev-2025-11-18-16-30-def5678
├── worker-dev-latest
├── dev-latest                          # Points to most recent build
├── api-prod-2025-11-18-16-45-ghi9012
└── api-prod-latest
```

**Benefits:**
- **Single repository:** Simpler IAM permissions and lifecycle policies
- **Clear organization:** Folder structure mirrors code structure
- **Service isolation:** Each service has its own tags
- **Easy deployment:** Deploy specific service with `api-dev-latest`
- **Rollback support:** Service-specific rollback with `-latest` tags
- **Audit trail:** Timestamp and git SHA in every tag

#### Using Multi-Service with Scripts

**docker-push.sh:**
```bash
# Push API service to dev
./scripts/docker-push.sh dev <YOUR-PROJECT> backend/api/Dockerfile.lambda

# Push worker service to dev
./scripts/docker-push.sh dev <YOUR-PROJECT> backend/worker/Dockerfile.lambda
```

**generate-workflows.sh:**

The workflow generator automatically creates workflows for each service folder it detects in `backend/`:

```bash
# Generates workflows for all services in backend/
./scripts/generate-workflows.sh

# Creates:
# - .github/workflows/deploy-lambda-api-dev.yml
# - .github/workflows/deploy-lambda-api-prod.yml
# - .github/workflows/deploy-lambda-worker-dev.yml
# - .github/workflows/deploy-lambda-worker-prod.yml
```

Each workflow sets `SERVICE_FOLDER` appropriately:
```yaml
env:
  SERVICE_FOLDER: backend/api  # or backend/worker
```

---

### 7. `test-api.sh`

**Purpose**: Comprehensive automated testing of all API endpoints after deployment.

**Location**: `scripts/test-api.sh`

**Usage**:
```bash
# Run using make
make test-api

# Or run directly
./scripts/test-api.sh
```

**What it does**:
1. Validates prerequisites (jq, curl, terraform directory)
2. Reads Terraform outputs to get API endpoint URL
3. Detects API Key authentication if enabled
4. Tests all endpoints with proper HTTP status code validation:
   - **Health checks**: `/health`, `/liveness`, `/readiness`
   - **Application endpoints**: `/`, `/greet` (GET/POST)
   - **Error handling**: `/error`, validation errors
5. Provides color-coded pass/fail results
6. Exits with error code if any test fails (CI/CD friendly)

**Example Output**:
```
🔍 Validating prerequisites...
✅ Prerequisites validated

📖 Reading Terraform outputs...
✅ Configuration loaded
   API URL: https://abc123.execute-api.us-east-1.amazonaws.com/
   Deployment Mode: api_gateway_standard
   API Key: Enabled (will be used in requests)

════════════════════════════════════════════════════════════
                    API ENDPOINT TESTS
════════════════════════════════════════════════════════════

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Health Check Endpoints
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Testing: Health check endpoint... ✓ PASS (HTTP 200)
{
  "status": "healthy",
  "timestamp": "2025-01-20T12:34:56.789012+00:00",
  "uptime_seconds": 123.45,
  "version": "0.1.0"
}

Testing: Liveness probe... ✓ PASS (HTTP 200)
Testing: Readiness probe... ✓ PASS (HTTP 200)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Application Endpoints
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Testing: Root endpoint... ✓ PASS (HTTP 200)
Testing: Greet with default name... ✓ PASS (HTTP 200)
Testing: Greet with query parameter... ✓ PASS (HTTP 200)
Testing: Greet with POST body... ✓ PASS (HTTP 200)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Error Handling
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Testing: Error endpoint (test error handling)... ✓ PASS (HTTP 500)
Testing: Validation error (missing required field)... ✓ PASS (HTTP 422)

════════════════════════════════════════════════════════════
                  ✓ ALL TESTS PASSED!
════════════════════════════════════════════════════════════

📊 Test Summary:
   • Health checks: 3/3 passed
   • Application endpoints: 4/4 passed
   • Error handling: 2/2 passed
   • Total: 9/9 tests passed

📖 Next Steps:
   • View interactive API docs: https://abc123.execute-api.us-east-1.amazonaws.com/docs
   • View alternative docs: https://abc123.execute-api.us-east-1.amazonaws.com/redoc
```

**When to run**:
- After deploying application infrastructure (`make app-apply-dev`)
- After updating Lambda function code
- In CI/CD pipelines for automated validation
- Before promoting to production
- When troubleshooting API issues

**Features**:
- ✅ Automatic API Key detection and usage
- ✅ Color-coded output for easy scanning
- ✅ JSON response pretty-printing with jq
- ✅ Proper exit codes (0 = success, 1 = failure)
- ✅ Validates all endpoint types (health, app, errors)
- ✅ Works with both API Gateway and Lambda Function URLs

**Prerequisites**:
- `jq` - JSON processor for pretty-printing responses
- `curl` - HTTP client for making requests
- Terraform outputs available (run from project root)

**CI/CD Integration**:
```yaml
# .github/workflows/deploy.yml
- name: Test API endpoints
  run: make test-api
```

**Exit Codes**:
- `0` - All tests passed
- `1` - One or more tests failed or prerequisites missing

---

## 🔄 Typical Workflow

### Initial Setup

```bash
# 1. Deploy bootstrap infrastructure
make bootstrap-apply

# 2. Generate Terraform backend configuration
make setup-terraform-backend

# 3. Create base Terraform files (run once)
./scripts/setup-terraform-base.sh

# 4. Add your first service (Lambda or AppRunner)
./scripts/setup-terraform-lambda.sh api false
# or
./scripts/setup-terraform-apprunner.sh runner

# 5. Build and deploy
./scripts/docker-push.sh dev api Dockerfile.lambda
make app-init-dev app-apply-dev
```

### Adding Additional Services

```bash
# 1. Create service directory
mkdir -p backend/worker
cp -r backend/api/* backend/worker/

# 2. Generate Terraform configuration
./scripts/setup-terraform-lambda.sh worker

# 3. Build and push
./scripts/docker-push.sh dev worker Dockerfile.lambda

# 4. Deploy
make app-apply-dev
```

### Daily Development

```bash
# Build and push Docker image
make docker-push-dev

# Or push directly for specific service
./scripts/docker-push.sh dev api Dockerfile.lambda
./scripts/docker-push.sh dev worker Dockerfile.lambda
```

---

## 🛠️ Script Requirements

### `setup-pre-commit.sh`

- ✅ `uv` installed
- ✅ Git repository initialized
- ✅ `pyproject.toml.example` (included in repo)

### `setup-terraform-backend.sh`

- ✅ Bootstrap Terraform initialized and applied
- ✅ `terraform` CLI installed
- ✅ `jq` (optional, for JSON parsing)

### `setup-terraform-base.sh`

- ✅ Bootstrap Terraform applied
- ✅ `terraform` CLI installed
- ✅ `bootstrap/terraform.tfvars` configured

### `setup-terraform-lambda.sh`

- ✅ Base Terraform files created (`setup-terraform-base.sh` run)
- ✅ Service directory exists in `backend/<service>/`
- ✅ Bootstrap Terraform applied

### `setup-terraform-apprunner.sh`

- ✅ Base Terraform files created (`setup-terraform-base.sh` run)
- ✅ Service directory exists in `backend/<service>/`
- ✅ Bootstrap Terraform applied

### `docker-push.sh`
- ✅ Bootstrap Terraform applied
- ✅ Docker installed and running
- ✅ AWS CLI configured
- ✅ AWS credentials with ECR permissions
- ✅ Git (optional, for SHA tagging)

### `generate-workflows.sh`
- ✅ Bootstrap Terraform applied
- ✅ `jq` installed (for JSON parsing)

**Install jq**:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Or download binary from https://stedolan.github.io/jq/
```

---

## 🐛 Troubleshooting

### Backend setup fails
**Problem**: "Error: Bootstrap directory not found"

**Solution**:
```bash
cd bootstrap/
terraform init
terraform apply
cd ..
./scripts/setup-terraform-backend.sh
```

### Docker push fails with auth error
**Problem**: "Error: Failed to login to ECR"

**Solution**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Manually login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Then retry
./scripts/docker-push.sh dev
```

### Workflow generation produces empty workflows
**Problem**: No feature flags detected

**Solution**:
```bash
# Verify bootstrap outputs
cd bootstrap/
terraform output summary

# Should show enabled_features
# If not, update terraform.tfvars and re-apply
```

---

## 📝 Script Maintenance

All scripts are designed to be:
- **Self-contained**: No external dependencies except CLI tools
- **Idempotent**: Safe to run multiple times
- **Verbose**: Clear output with color-coding
- **Error-handling**: Validates inputs and exits gracefully

To modify scripts:
1. Edit in `scripts/` directory
2. Test with `bash -x scripts/script-name.sh` for debugging
3. Ensure executable: `chmod +x scripts/script-name.sh`
4. Update this documentation

---

## 🔗 Related Documentation

- [README.md](../README.md) - Main project documentation
- [Bootstrap outputs](../bootstrap/outputs.tf) - Available Terraform outputs
- [GitHub Actions docs](https://docs.github.com/en/actions)

---

**Questions or issues?** Open an issue or check the troubleshooting section in the main README.
