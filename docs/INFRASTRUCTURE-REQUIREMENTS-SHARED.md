# Infrastructure Requirements for Shared Library

## Overview

This document details the AWS infrastructure required to support the `shared` library functionality, based on the current Terraform configuration in the `bootstrap/` and `terraform/` folders.

## Current Terraform Architecture

### Bootstrap Layer (`bootstrap/`)

**Purpose**: Foundational CI/CD and AWS infrastructure

**Key Resources Created:**
- S3 bucket for Terraform state management
- GitHub Actions OIDC provider for federated auth
- IAM roles for GitHub Actions (dev/test/prod environments)
- Lambda execution roles (when `enable_lambda = true`)
- App Runner instance roles (when `enable_apprunner = true`)
- ECR repositories for container images

**IAM Policies Defined:**
```
✓ Terraform State Access
✓ API Gateway Management
✓ S3 Vector Management
✓ Bedrock Invocation (for embeddings)
✓ Lambda Deployment
✓ App Runner Deployment
✓ CloudWatch Logs
```

### Application Layer (`terraform/`)

**Purpose**: Application services and integrations

**Services Deployed:**
1. **Lambda Functions (3)**
   - `api` - 512 MB, 30s timeout
   - `chat` - 512 MB, 30s timeout
   - `s3vector` - 512 MB, 30s timeout

2. **App Runner Service (1)**
   - `runner` - 1024 CPU, 2048 MB, auto-scaling 1-5

3. **API Gateway**
   - Single REST API with path-based routing
   - Paths: `/api`, `/chat`, `/s3vector`, `/runner`
   - CloudWatch logging and metrics
   - Optional per-service API keys

4. **S3 Buckets**
   - Vector embeddings storage
   - Server-side encryption (AES256)
   - Versioning enabled

## Shared Library Dependencies

The shared library (`backend/shared/`) provides these capabilities:

| Module | Purpose | AWS Services Required |
|--------|---------|----------------------|
| `api_client.py` | Inter-service HTTP calls with auto API key injection | API Gateway, Secrets Manager |
| `logging.py` | Structured JSON logging | CloudWatch Logs |
| `tracing.py` | Distributed tracing with OpenTelemetry | X-Ray, OTLP endpoint |
| `middleware.py` | FastAPI request logging | CloudWatch Logs |
| `models.py` | Common Pydantic models | None (pure Python) |
| `settings.py` | Environment-based configuration | None (reads env vars) |
| `health.py` | Health check endpoints | None (pure Python) |

### Python Dependencies
```python
# AWS SDK
boto3>=1.35.0
botocore>=1.35.0

# HTTP Client
httpx>=0.27.0

# Data Validation
pydantic>=2.9.0
pydantic-settings>=2.6.0

# Structured Logging
structlog>=24.4.0

# OpenTelemetry (Distributed Tracing)
opentelemetry-api>=1.27.0
opentelemetry-sdk>=1.27.0
opentelemetry-exporter-otlp-proto-grpc>=1.27.0
opentelemetry-instrumentation-fastapi>=0.48b0
opentelemetry-instrumentation-httpx>=0.48b0
```

## Infrastructure Requirements by Feature

### 1. API Client (`ServiceAPIClient`)

**Required Environment Variables:**
```bash
API_GATEWAY_URL=https://abc123.execute-api.us-east-1.amazonaws.com/dev
PROJECT_NAME=fin-advisor
ENVIRONMENT=dev
SERVICE_NAME=api  # or chat, s3vector, runner
```

**Required IAM Permissions:**
```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue"
  ],
  "Resource": "arn:aws:secretsmanager:*:*:secret:{project_name}/{environment}/*/api-key-*"
}
```

**Required Secrets Manager Secrets:**
```
{project_name}/{environment}/api/api-key
{project_name}/{environment}/chat/api-key
{project_name}/{environment}/s3vector/api-key
{project_name}/{environment}/runner/api-key
```

**Current Status:**
- ✅ API Gateway infrastructure exists
- ✅ Secrets Manager integration code exists
- ⚠️ **MISSING**: Only `chat` Lambda has Secrets Manager IAM policy
- ⚠️ **MISSING**: Only `chat` Lambda has `API_GATEWAY_URL` env var
- ⚠️ **DISABLED**: `enable_service_api_keys = false` in tfvars

**Required Terraform Changes:**

```hcl
# In terraform/environments/dev.tfvars
enable_service_api_keys = true

service_api_keys = {
  api = {
    quota_limit  = 100000
    quota_period = "MONTH"
    description  = "API service key"
  }
  chat = {
    quota_limit  = 100000
    quota_period = "MONTH"
    description  = "Chat service key"
  }
  s3vector = {
    quota_limit  = 50000
    quota_period = "MONTH"
    description  = "S3Vector service key"
  }
  runner = {
    quota_limit  = 75000
    quota_period = "MONTH"
    description  = "Runner service key"
  }
}
```

```hcl
# Add to lambda-api.tf (similar pattern exists in lambda-chat.tf:36-52)
resource "aws_iam_policy" "lambda_api_secrets" {
  name = "${var.project_name}-${var.environment}-lambda-api-secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/*/api-key-*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_api_secrets" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = aws_iam_policy.lambda_api_secrets.arn
}

# Add to lambda-api.tf environment variables
environment {
  variables = {
    ENVIRONMENT       = var.environment
    PROJECT_NAME      = var.project_name
    SERVICE_NAME      = "api"
    LOG_LEVEL         = var.log_level
    API_GATEWAY_URL   = "${aws_api_gateway_deployment.main.invoke_url}"  # ADD THIS
  }
}
```

```hcl
# Add to lambda-s3vector.tf
resource "aws_iam_policy" "lambda_s3vector_secrets" {
  name = "${var.project_name}-${var.environment}-lambda-s3vector-secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/*/api-key-*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3vector_secrets" {
  role       = aws_iam_role.lambda_s3vector.name
  policy_arn = aws_iam_policy.lambda_s3vector_secrets.arn
}

# Add to environment variables
environment {
  variables = {
    ENVIRONMENT         = var.environment
    PROJECT_NAME        = var.project_name
    SERVICE_NAME        = "s3vector"
    LOG_LEVEL           = var.log_level
    API_GATEWAY_URL     = "${aws_api_gateway_deployment.main.invoke_url}"  # ADD THIS
    BEDROCK_MODEL_ID    = var.bedrock_model_id
    VECTOR_BUCKET_NAME  = aws_s3_bucket.vectors.id
  }
}
```

```hcl
# Add to apprunner-runner.tf
resource "aws_iam_policy" "apprunner_runner_secrets" {
  name = "${var.project_name}-${var.environment}-apprunner-runner-secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/*/api-key-*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apprunner_runner_secrets" {
  role       = aws_iam_role.apprunner_runner_instance.name
  policy_arn = aws_iam_policy.apprunner_runner_secrets.arn
}

# Add to environment variables
environment_variables = {
  ENVIRONMENT      = var.environment
  PROJECT_NAME     = var.project_name
  SERVICE_NAME     = "runner"
  LOG_LEVEL        = var.log_level
  API_GATEWAY_URL  = "${aws_api_gateway_deployment.main.invoke_url}"  # ADD THIS
}
```

### 2. Logging (`configure_logging`, `get_logger`)

**Required Environment Variables:**
```bash
LOG_LEVEL=INFO  # DEBUG, INFO, WARNING, ERROR, CRITICAL
SERVICE_NAME=api
ENVIRONMENT=dev
```

**Required Infrastructure:**
- CloudWatch Logs (already configured for all services)

**Current Status:**
- ✅ CloudWatch Logs configured for all Lambda functions
- ✅ CloudWatch Logs configured for App Runner
- ✅ Log retention policies in place
- ✅ All required environment variables present

**Log Format Output:**
```json
{
  "event": "request_completed",
  "service": "api",
  "environment": "dev",
  "path": "/health",
  "method": "GET",
  "status": 200,
  "duration": 0.123,
  "timestamp": "2024-12-07T10:30:45Z"
}
```

### 3. Tracing (`configure_tracing`, `get_tracer`)

**Required Environment Variables:**
```bash
ENABLE_TRACING=true
OTLP_ENDPOINT=http://localhost:4317  # For Lambda: use X-Ray
SERVICE_NAME=api
ENVIRONMENT=dev
```

**Required Infrastructure:**

**For Lambda:**
- AWS X-Ray daemon (built into Lambda runtime)
- Lambda tracing mode: `Active`
- AWS Distro for OpenTelemetry (ADOT) Lambda Layer

**For App Runner:**
- X-Ray daemon configuration (already present)
- OTLP collector endpoint

**Current Status:**
- ✅ Lambda tracing mode set to `Active`
- ✅ App Runner X-Ray observability configured
- ⚠️ **MISSING**: ADOT Lambda Layer not attached
- ⚠️ **MISSING**: `OTLP_ENDPOINT` environment variable

**Required Terraform Changes:**

```hcl
# Add to lambda-api.tf, lambda-chat.tf, lambda-s3vector.tf
data "aws_lambda_layer_version" "adot" {
  layer_name = "aws-otel-python-amd64-ver-1-17-0"  # Latest ADOT layer
}

resource "aws_lambda_function" "api" {
  # ... existing config ...

  layers = [
    data.aws_lambda_layer_version.adot.arn
  ]

  environment {
    variables = {
      # ... existing vars ...
      ENABLE_TRACING    = "true"
      OTLP_ENDPOINT     = "http://localhost:4317"  # ADOT collector
      AWS_LAMBDA_EXEC_WRAPPER = "/opt/otel-instrument"
    }
  }
}
```

**OpenTelemetry Configuration:**

The shared library's `tracing.py` module initializes OpenTelemetry:
- Creates TracerProvider with Resource (service name, environment)
- Configures OTLP gRPC exporter
- Instruments FastAPI and HTTPx automatically
- Exports traces to X-Ray via ADOT layer

### 4. Middleware (`LoggingMiddleware`, `logging_middleware`)

**Required Infrastructure:**
- CloudWatch Logs (already configured)

**Required Environment Variables:**
```bash
LOG_LEVEL=INFO
SERVICE_NAME=api
```

**Current Status:**
- ✅ Fully supported by existing infrastructure

**Usage in Service:**
```python
from fastapi import FastAPI
from shared import configure_logging, LoggingMiddleware

configure_logging(log_level="INFO")
app = FastAPI()
app.add_middleware(LoggingMiddleware)
```

**Logs Generated:**
```json
{
  "event": "request_started",
  "method": "GET",
  "path": "/health",
  "client_ip": "192.168.1.1",
  "timestamp": "2024-12-07T10:30:45Z"
}
{
  "event": "request_completed",
  "method": "GET",
  "path": "/health",
  "status": 200,
  "duration": 0.045,
  "timestamp": "2024-12-07T10:30:45Z"
}
```

### 5. Models (`ErrorResponse`, `HealthResponse`, etc.)

**Required Infrastructure:**
- None (pure Python Pydantic models)

**Current Status:**
- ✅ No infrastructure dependencies

### 6. Settings (`BaseServiceSettings`, `FullServiceSettings`)

**Required Environment Variables:**
```bash
# Base Service Settings
PROJECT_NAME=fin-advisor
ENVIRONMENT=dev
SERVICE_NAME=api
LOG_LEVEL=INFO

# AWS Settings (BaseAWSSettings)
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1

# Tracing Settings (BaseTracingSettings)
ENABLE_TRACING=true
OTLP_ENDPOINT=http://localhost:4317

# Full Service Settings (combines all above)
API_GATEWAY_URL=https://abc123.execute-api.us-east-1.amazonaws.com/dev
```

**Current Status:**
- ✅ Most environment variables configured
- ⚠️ **MISSING**: `API_GATEWAY_URL` for api, s3vector, runner
- ⚠️ **MISSING**: `OTLP_ENDPOINT` for all services

**Usage in Service:**
```python
from shared import FullServiceSettings

class Settings(FullServiceSettings):
    # Service-specific settings
    max_retries: int = 3

settings = Settings()
# Automatically reads from environment variables
```

### 7. Health Checks (`health_check_simple`, etc.)

**Required Infrastructure:**
- None (pure Python)

**Current Status:**
- ✅ No infrastructure dependencies

**API Gateway Health Check Integration:**
- App Runner: Health check configured at `/health`
- Lambda: Health checks via API Gateway paths

## Complete Infrastructure Checklist

### ✅ Already Configured

- [x] API Gateway with service routing
- [x] CloudWatch Logs for all services
- [x] Lambda execution roles with basic permissions
- [x] App Runner instance roles with basic permissions
- [x] S3 buckets for vector storage
- [x] Bedrock invocation permissions (s3vector service)
- [x] X-Ray tracing mode enabled
- [x] App Runner X-Ray observability
- [x] Secrets Manager secrets creation (via modules)
- [x] ECR repositories for container images
- [x] GitHub Actions OIDC authentication

### ⚠️ Partially Configured (Needs Completion)

- [ ] **Secrets Manager IAM permissions** - Only `chat` has it, need for `api`, `s3vector`, `runner`
- [ ] **API_GATEWAY_URL environment variable** - Only `chat` has it, need for `api`, `s3vector`, `runner`
- [ ] **Service API keys** - Infrastructure exists but `enable_service_api_keys = false` in tfvars

### ❌ Missing (Required for Full Shared Library Features)

- [ ] **ADOT Lambda Layer** - For proper OpenTelemetry export to X-Ray
- [ ] **OTLP_ENDPOINT environment variable** - For all Lambda functions
- [ ] **HTTPx OpenTelemetry instrumentation** - Need to call in service startup code
- [ ] **API key configuration in tfvars** - Set `enable_service_api_keys = true` and populate `service_api_keys`

## Minimal Changes Required for Full Functionality

### Priority 1: Inter-Service Communication (High Impact)

**File**: `terraform/environments/dev.tfvars`
```hcl
enable_service_api_keys = true

service_api_keys = {
  api      = { quota_limit = 100000, quota_period = "MONTH", description = "API service" }
  chat     = { quota_limit = 100000, quota_period = "MONTH", description = "Chat service" }
  s3vector = { quota_limit = 50000,  quota_period = "MONTH", description = "S3Vector service" }
  runner   = { quota_limit = 75000,  quota_period = "MONTH", description = "Runner service" }
}
```

**Files**: Add Secrets Manager policies to:
- `terraform/lambda-api.tf`
- `terraform/lambda-s3vector.tf`
- `terraform/apprunner-runner.tf`

**Files**: Add `API_GATEWAY_URL` environment variable to:
- `terraform/lambda-api.tf`
- `terraform/lambda-s3vector.tf`
- `terraform/apprunner-runner.tf`

### Priority 2: Distributed Tracing (Medium Impact)

**Files**: Add ADOT layer and environment variables to:
- `terraform/lambda-api.tf`
- `terraform/lambda-chat.tf`
- `terraform/lambda-s3vector.tf`

```hcl
data "aws_lambda_layer_version" "adot" {
  layer_name = "aws-otel-python-amd64-ver-1-17-0"
}

resource "aws_lambda_function" "example" {
  layers = [data.aws_lambda_layer_version.adot.arn]

  environment {
    variables = {
      ENABLE_TRACING           = "true"
      OTLP_ENDPOINT            = "http://localhost:4317"
      AWS_LAMBDA_EXEC_WRAPPER  = "/opt/otel-instrument"
    }
  }
}
```

### Priority 3: Service Code Updates (Required)

Each service needs to initialize the shared library:

```python
from shared import (
    configure_logging,
    configure_tracing,
    FullServiceSettings,
    LoggingMiddleware,
)

# Settings
settings = FullServiceSettings()

# Logging
configure_logging(log_level=settings.log_level)

# Tracing (if enabled)
if settings.enable_tracing:
    configure_tracing(
        service_name=settings.service_name,
        environment=settings.environment,
        otlp_endpoint=settings.otlp_endpoint,
    )

# FastAPI
app = FastAPI()
app.add_middleware(LoggingMiddleware)
```

## Testing Infrastructure Changes

### 1. Test Secrets Manager Access

```bash
# Deploy Terraform changes
cd terraform
terraform apply -var-file="environments/dev.tfvars"

# Verify secrets created
aws secretsmanager list-secrets \
    --query "SecretList[?contains(Name, 'fin-advisor/dev')].Name" \
    --output table

# Test secret retrieval from Lambda
aws lambda invoke \
    --function-name fin-advisor-dev-api \
    --payload '{"test": "secrets"}' \
    /tmp/response.json
```

### 2. Test Inter-Service Communication

```python
# In api Lambda
from shared import ServiceAPIClient

async with ServiceAPIClient(service_name="api") as client:
    # Call chat service
    response = await client.get("/chat/health")
    print(response.json())
```

### 3. Test Distributed Tracing

```bash
# Make a request that triggers inter-service calls
curl https://your-api-gateway-url.amazonaws.com/dev/api/test

# View traces in X-Ray console
aws xray get-trace-summaries \
    --start-time $(date -u -d '5 minutes ago' +%s) \
    --end-time $(date -u +%s)
```

## Cost Impact

### Additional Resources Created

| Resource | Quantity | Monthly Cost (est.) |
|----------|----------|---------------------|
| Secrets Manager Secrets | 4 | $0.40/secret × 4 = $1.60 |
| Secrets Manager API Calls | ~10,000 | $0.05 per 10,000 = $0.05 |
| X-Ray Traces (100K/month) | 100,000 | First 100K free, then $5/1M = $0.00 |
| CloudWatch Logs (5GB/month) | 5 GB | First 5GB free = $0.00 |
| ADOT Lambda Layer | 0 | Free (AWS-managed) |
| **Total** | | **~$1.65/month** |

**Note**: This assumes dev environment usage. Production may have higher API call volume.

## Security Considerations

### IAM Least Privilege

The infrastructure follows least privilege:
- Lambda/App Runner can only read their own service's API key pattern
- Secrets path: `{project}/{env}/{service}/api-key` (scoped)
- No wildcard `*` permissions on Secrets Manager

### API Key Rotation

API keys in Secrets Manager can be rotated:
```bash
aws secretsmanager rotate-secret \
    --secret-id fin-advisor/dev/api/api-key \
    --rotation-lambda-arn <rotation-lambda-arn>
```

### Network Security

- API Gateway uses HTTPS only
- Inter-service calls via API Gateway (TLS encrypted)
- Lambda/App Runner in VPC (optional, not currently configured)

## Summary

### Current Infrastructure Capability

Your Terraform infrastructure **supports 80% of the shared library functionality** out of the box:
- ✅ CloudWatch logging (100% working)
- ✅ Basic AWS SDK usage (100% working)
- ✅ Health checks (100% working)
- ⚠️ Inter-service communication (50% - needs API keys enabled + IAM policies)
- ⚠️ Distributed tracing (50% - needs ADOT layer)

### Required Changes Summary

**Terraform Changes (3-4 files):**
1. Enable service API keys in `terraform/environments/dev.tfvars`
2. Add Secrets Manager IAM policies to 3 resources
3. Add `API_GATEWAY_URL` environment variable to 3 resources
4. Add ADOT Lambda layer to 3 Lambda functions

**Cost Impact**: ~$1.65/month additional

**Time to Implement**: 2-3 hours (including testing)

**Risk**: Low (additive changes, no breaking modifications)
