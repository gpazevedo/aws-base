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
bucket       = "my-project-terraform-state-123456789012"
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

### 3. `setup-terraform-lambda.sh`

**Purpose**: Generates example Terraform configuration files for Lambda-based application infrastructure.

**Location**: `scripts/setup-terraform-lambda.sh`

**Usage**:
```bash
./scripts/setup-terraform-lambda.sh
# or
make setup-terraform-lambda
```

**What it does**:
1. Reads project configuration from `bootstrap/terraform.tfvars` (if available)
2. Creates `terraform/` directory structure
3. Generates complete Terraform configuration for Lambda deployment:
   - `terraform/main.tf` - Provider and backend configuration
   - `terraform/variables.tf` - Variable definitions
   - `terraform/lambda.tf` - Lambda function with container image
   - `terraform/api-gateway.tf` - Optional API Gateway setup
   - `terraform/outputs.tf` - Output values
   - `terraform/README.md` - Documentation
4. Creates environment-specific variable files:
   - `terraform/environments/dev.tfvars`
   - `terraform/environments/test.tfvars`
   - `terraform/environments/prod.tfvars`

**Generated infrastructure features**:
- Lambda function using container images from ECR
- Lambda Function URLs (no API Gateway needed by default)
- CloudWatch Logs with JSON formatting and retention policies
- Environment-specific memory/timeout configurations
- Lifecycle rules for CI/CD compatibility
- Optional API Gateway integration

**When to run**:
- After completing bootstrap setup
- When starting a new Lambda-based project
- To get example Terraform configuration for reference

**Customization**:
After generation, you can:
- Edit environment variable files (`terraform/environments/*.tfvars`)
- Modify Lambda configuration in `terraform/lambda.tf`
- Add additional resources (DynamoDB, SQS, etc.)
- Enable API Gateway by setting `enable_api_gateway = true`

**Example workflow**:
```bash
# 1. Generate application Terraform files
make setup-terraform-lambda

# 2. Customize the generated files
vim terraform/environments/dev.tfvars

# 3. Build and push Docker image
make docker-build
make docker-push-dev

# 4. Deploy application
make app-init-dev
make app-plan-dev
make app-apply-dev
```

---

### 4. `setup-terraform-apprunner.sh`

**Purpose**: Generates example Terraform configuration files for App Runner-based application infrastructure.

**Location**: `scripts/setup-terraform-apprunner.sh`

**Usage**:
```bash
./scripts/setup-terraform-apprunner.sh
# or
make setup-terraform-apprunner
```

**What it does**:
1. Reads project configuration from `bootstrap/terraform.tfvars` (if available)
2. Creates `terraform/` directory structure
3. Generates complete Terraform configuration for App Runner deployment:
   - `terraform/main.tf` - Provider and backend configuration
   - `terraform/variables.tf` - Variable definitions (CPU, memory, auto-scaling)
   - `terraform/apprunner.tf` - App Runner service with container image
   - `terraform/api-gateway.tf` - Optional API Gateway with HTTP_PROXY integration
   - `terraform/outputs.tf` - Output values
   - `terraform/README.md` - Documentation with App Runner vs Lambda comparison
4. Creates environment-specific variable files:
   - `terraform/environments/dev.tfvars`
   - `terraform/environments/test.tfvars`
   - `terraform/environments/prod.tfvars`

**Generated infrastructure features**:
- App Runner service using container images from ECR
- Auto-scaling configuration (min/max instances, concurrency)
- Health check configuration
- CloudWatch Logs integration via IAM instance role
- Environment-specific CPU/memory configurations
- Lifecycle rules for CI/CD compatibility
- Optional API Gateway integration with HTTP_PROXY

**When to run**:
- After completing bootstrap setup with `enable_apprunner = true`
- When starting a new containerized web application project
- For long-running web services with WebSocket support
- When you need minimal cold starts compared to Lambda

**App Runner vs Lambda**:
Use **App Runner** when:
- ✅ Building long-running web applications
- ✅ Need WebSocket or streaming support
- ✅ Want consistent performance (minimal cold starts)
- ✅ Prefer instance-based pricing over per-request pricing
- ✅ Need full control over web server configuration

Use **Lambda** (via `setup-terraform-lambda.sh`) when:
- ✅ Event-driven workloads
- ✅ Sporadic traffic patterns
- ✅ Simple request/response APIs
- ✅ Need massive auto-scaling

**Customization**:
After generation, you can:
- Edit environment variable files (`terraform/environments/*.tfvars`)
- Adjust CPU/memory sizing in `terraform/apprunner.tf`
- Configure auto-scaling parameters (min/max instances, concurrency)
- Customize health check settings
- Enable API Gateway by setting `enable_api_gateway_standard = true`
- Add additional resources (RDS, ElastiCache, etc.)

**Example workflow**:
```bash
# 1. Generate App Runner Terraform files
make setup-terraform-apprunner

# 2. Customize the generated files
vim terraform/environments/dev.tfvars

# 3. Build and push Docker image
make docker-build DOCKERFILE=Dockerfile.apprunner
make docker-push-dev

# 4. Deploy application
make app-init-dev
make app-plan-dev
make app-apply-dev
```

**Key configuration variables**:
```hcl
# CPU/Memory sizing (see AWS App Runner documentation for valid combinations)
apprunner_cpu    = "1024"  # 256, 512, 1024, 2048, 4096
apprunner_memory = "2048"  # 512-12288 MB

# Auto-scaling
apprunner_min_instances  = 1
apprunner_max_instances  = 10
apprunner_max_concurrency = 100  # Concurrent requests per instance

# Health checks
health_check_path = "/health"
health_check_interval = 10
```

---

### 5. `docker-push.sh`

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
          role-to-assume: arn:aws:iam::123456789012:role/my-project-github-actions-dev
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
            --function-name my-project-dev-api \
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
- Repository: `123456789.dkr.ecr.us-east-1.amazonaws.com/my-project`
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
  -t my-project:api-dev-latest \
  backend/api

# Build worker service
docker build \
  --build-arg SERVICE_FOLDER=backend/worker \
  -f backend/worker/Dockerfile.lambda \
  -t my-project:worker-dev-latest \
  backend/worker
```

**Image Tag Hierarchy in Single ECR Repository:**

All services share one ECR repository but are organized hierarchically:

```
my-project/  (single ECR repository)
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
./scripts/docker-push.sh dev my-project backend/api/Dockerfile.lambda

# Push worker service to dev
./scripts/docker-push.sh dev my-project backend/worker/Dockerfile.lambda
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

### 6. `sync-tfvars-to-env.py`

**Purpose**: Sync variables from `terraform.tfvars` (and Terraform outputs) to `.env` file for use in shell scripts, Docker, and applications.

**Location**: `scripts/sync-tfvars-to-env.py`

**Usage**:
```bash
# Sync bootstrap terraform.tfvars to .env (no prefix)
./scripts/sync-tfvars-to-env.py
# or
make sync-env

# Custom files
./scripts/sync-tfvars-to-env.py --tfvars custom.tfvars --env custom.env

# Add TF_VAR_ prefix (for Terraform input variables)
./scripts/sync-tfvars-to-env.py --tf-var-prefix

# Custom prefix
./scripts/sync-tfvars-to-env.py --prefix "APP_"

# Overwrite .env completely (default: merge)
./scripts/sync-tfvars-to-env.py --overwrite
```

**What it does**:
1. Parses `terraform.tfvars` file (no external dependencies)
2. Converts Terraform variables to environment variable format
3. Writes to `.env` file with proper formatting
4. **No prefix by default** (clean variable names for shell/Docker/apps)
5. Merges with existing `.env` (unless `--overwrite`)

**Variable Conversion**:
```hcl
# terraform.tfvars or outputs
project_name = "my-app"
enable_lambda = true
lambda_timeout = 300
ecr_repositories = ["api", "worker"]
lambda_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:my-app"
```

```bash
# .env (generated - no prefix)
PROJECT_NAME=my-app
ENABLE_LAMBDA=true
LAMBDA_TIMEOUT=300
ECR_REPOSITORIES=api,worker
LAMBDA_FUNCTION_ARN=arn:aws:lambda:us-east-1:123456789012:function:my-app
```

**Options**:
- `--tfvars PATH` - Path to terraform.tfvars (default: `bootstrap/terraform.tfvars`)
- `--env PATH` - Path to .env file (default: `.env`)
- `--prefix PREFIX` - Variable prefix (default: none)
- `--tf-var-prefix` - Add TF_VAR_ prefix (for Terraform input variables)
- `--overwrite` - Overwrite .env completely (default: merge)

**When to run**:
- After `terraform apply` to capture resource ARNs and IDs
- After creating/updating `terraform.tfvars`
- Before running shell scripts that need Terraform outputs
- To share configuration between Terraform and application code

**Use cases**:
```bash
# Use Terraform outputs in shell scripts
terraform output -json > outputs.tfvars  # Export outputs
./scripts/sync-tfvars-to-env.py --tfvars outputs.tfvars
source .env
aws lambda invoke --function-name $LAMBDA_FUNCTION_ARN output.json

# Use in Docker Compose
docker-compose --env-file .env up

# Use in GitHub Actions
- name: Load environment
  run: |
    source .env
    echo "LAMBDA_ARN=$LAMBDA_FUNCTION_ARN" >> $GITHUB_ENV
```

**Note**: The `.env` file is automatically added to `.gitignore` to prevent committing sensitive data.

---

## 🔄 Typical Workflow

### Initial Setup
```bash
# 1. Deploy bootstrap
make bootstrap-apply

# 2. Generate backend configs
make setup-terraform-backend

# 3. Sync tfvars to .env
make sync-env

### Daily Development
```bash
# Build and push Docker image
make docker-push-dev

# Or push directly
./scripts/docker-push.sh dev my-api Dockerfile.lambda
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

### `docker-push.sh`
- ✅ Bootstrap Terraform applied
- ✅ Docker installed and running
- ✅ AWS CLI configured
- ✅ AWS credentials with ECR permissions
- ✅ Git (optional, for SHA tagging)

### `generate-workflows.sh`
- ✅ Bootstrap Terraform applied
- ✅ `jq` installed (for JSON parsing)

### `sync-tfvars-to-env.py`
- ✅ `uv` installed (for `uv run python`)
- ✅ Python 3.13+ (included with uv)
- ✅ `terraform.tfvars` file exists (default: `bootstrap/terraform.tfvars`)
- ❌ No external Python packages required (pure Python)

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
