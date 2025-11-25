# Adding New Services Guide

Step-by-step instructions for adding new Lambda and AppRunner services to your infrastructure.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Adding a Lambda Service](#adding-a-lambda-service)
- [Adding an AppRunner Service](#adding-an-apprunner-service)
- [Service Naming Conventions](#service-naming-conventions)
- [Testing Your New Service](#testing-your-new-service)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before adding new services, ensure you have:

- ✅ Bootstrap infrastructure deployed (`make bootstrap-apply`)
- ✅ At least one service already deployed (the first service creates API Gateway)
- ✅ AWS CLI configured with appropriate credentials
- ✅ Terraform installed (>= 1.13.0)
- ✅ Docker installed and running
- ✅ `uv` installed for Python package management

**Verify your setup:**

```bash
# Check AWS credentials
aws sts get-caller-identity

# Check Terraform
terraform version

# Check Docker
docker --version

# Check uv
uv --version
```

---

## Adding a Lambda Service

Lambda services are ideal for:
- REST APIs and HTTP endpoints
- Event processing (< 15 minutes runtime)
- Scheduled tasks and cron jobs
- Lightweight microservices

### Step 1: Create Service Infrastructure

Run the setup script to create Terraform configuration:

```bash
# Syntax: ./scripts/setup-terraform-lambda.sh <service-name> [enable_api_key]
./scripts/setup-terraform-lambda.sh worker

# Or with API key authentication enabled
./scripts/setup-terraform-lambda.sh worker true
```

**What this does:**
- Creates `terraform/lambda-worker.tf` with Lambda function definition
- Appends integration to `terraform/api-gateway.tf` (if it exists)
- Sets up path-based routing: `/worker/*`

**Script prompts:**
```
Creating Lambda service: worker
Enable API Key authentication? (true/false) [false]:
✓ Created terraform/lambda-worker.tf
✓ Appended API Gateway integration to terraform/api-gateway.tf
```

### Step 2: Create Backend Application Code

Create the service directory and application files:

```bash
# Create service directory
mkdir -p backend/worker

# Copy template from existing service
cp backend/api/main.py backend/worker/main.py
cp backend/api/pyproject.toml backend/worker/pyproject.toml
```

**Edit `backend/worker/main.py`:**

```python
"""Worker service - Background job processing."""

from fastapi import FastAPI
from mangum import Mangum
import time

# Create FastAPI app
app = FastAPI(
    title="Worker Service",
    description="Background job processing service",
    version="1.0.0"
)

# Track service start time
start_time = time.time()

@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "service": "worker",
        "message": "Worker service is running",
        "version": "1.0.0"
    }

@app.get("/health")
async def health():
    """Health check endpoint."""
    uptime = time.time() - start_time
    return {
        "status": "healthy",
        "service": "worker",
        "uptime_seconds": round(uptime, 2)
    }

@app.get("/liveness")
async def liveness():
    """Kubernetes-style liveness probe."""
    return {"status": "alive"}

@app.get("/readiness")
async def readiness():
    """Kubernetes-style readiness probe."""
    return {"status": "ready"}

@app.post("/jobs")
async def create_job(job_data: dict):
    """Create a new background job."""
    return {
        "message": "Job created",
        "job_id": "job-123",
        "data": job_data
    }

@app.get("/jobs/{job_id}")
async def get_job(job_id: str):
    """Get job status."""
    return {
        "job_id": job_id,
        "status": "processing",
        "progress": 50
    }

# Lambda handler
handler = Mangum(app, lifespan="off")
```

**Edit `backend/worker/pyproject.toml`:**

```toml
[project]
name = "worker"
version = "1.0.0"
description = "Worker service for background job processing"
requires-python = ">=3.13"
dependencies = [
    "fastapi>=0.115.6",
    "mangum>=0.19.0",
    "httpx>=0.27.2",
]

[project.optional-dependencies]
test = [
    "pytest>=8.3.4",
    "pytest-asyncio>=0.24.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

### Step 3: Install Dependencies and Test Locally

```bash
# Navigate to service directory
cd backend/worker

# Create virtual environment and install dependencies
uv sync

# Test locally (optional)
uv run uvicorn main:app --reload --port 8001

# In another terminal, test the endpoints
curl http://localhost:8001/health
curl http://localhost:8001/
curl -X POST http://localhost:8001/jobs -H "Content-Type: application/json" -d '{"task": "process_data"}'

# Stop the server (Ctrl+C) when done
cd ../..
```

### Step 4: Build and Push Docker Image

```bash
# Build and push to ECR
./scripts/docker-push.sh dev worker Dockerfile.lambda

# Expected output:
# Building Docker image for worker service (dev environment)
# Architecture: arm64 (from Dockerfile.lambda)
# ...
# ✓ Image pushed: <account>.dkr.ecr.us-east-1.amazonaws.com/<project>:worker-dev-latest
# ✓ Image pushed: <account>.dkr.ecr.us-east-1.amazonaws.com/<project>:worker-dev-2025-11-23-abc1234
```

**What this does:**
- Builds ARM64 image for Lambda (Graviton2)
- Pushes to ECR with two tags:
  - `worker-dev-latest` - Always points to latest
  - `worker-dev-YYYYMMDD-HHMMSS-SHA` - Specific version for rollback

### Step 5: Deploy Infrastructure

```bash
# Navigate to Terraform directory
cd terraform

# Review changes (optional but recommended)
terraform plan -var-file=environments/dev.tfvars

# Apply changes
terraform apply -var-file=environments/dev.tfvars

# Expected output:
# ...
# Plan: 4 to add, 1 to change, 0 to destroy
# ...
# Apply complete! Resources: 4 added, 1 changed, 0 destroyed.
```

**What gets created:**
- Lambda function: `<project>-dev-worker`
- CloudWatch Log Group: `/aws/lambda/<project>-dev-worker`
- API Gateway integration: `/worker`, `/worker/{proxy+}`
- IAM permissions for API Gateway to invoke Lambda

### Step 6: Test Deployed Service

```bash
# Get API Gateway URL
PRIMARY_URL=$(terraform output -raw primary_endpoint)

# Test worker service endpoints
curl $PRIMARY_URL/worker/health
curl $PRIMARY_URL/worker/
curl -X POST $PRIMARY_URL/worker/jobs -H "Content-Type: application/json" -d '{"task": "test"}'
curl $PRIMARY_URL/worker/jobs/job-123

# Or use the make target
cd ..
make test-lambda-worker
```

**Expected responses:**

```json
// GET /worker/health
{
  "status": "healthy",
  "service": "worker",
  "uptime_seconds": 12.34
}

// GET /worker/
{
  "service": "worker",
  "message": "Worker service is running",
  "version": "1.0.0"
}
```

### Step 7: Add Tests (Optional but Recommended)

Create `backend/worker/tests/test_worker.py`:

```python
"""Tests for worker service."""

import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health():
    """Test health endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
    assert response.json()["service"] == "worker"

def test_root():
    """Test root endpoint."""
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["service"] == "worker"

def test_create_job():
    """Test job creation."""
    response = client.post("/jobs", json={"task": "test_task"})
    assert response.status_code == 200
    assert "job_id" in response.json()

def test_get_job():
    """Test get job status."""
    response = client.get("/jobs/test-123")
    assert response.status_code == 200
    assert response.json()["job_id"] == "test-123"
```

Run tests:

```bash
cd backend/worker
uv run pytest
```

---

## Adding an AppRunner Service

AppRunner services are ideal for:
- Web applications with steady traffic
- Long-running processes (no 15-minute limit)
- Services requiring WebSocket connections
- Applications needing always-warm instances

### Step 1: Create Service Infrastructure

Run the setup script to create Terraform configuration:

```bash
# Syntax: ./scripts/setup-terraform-apprunner.sh <service-name>
./scripts/setup-terraform-apprunner.sh web
```

**Script prompts:**

```
Creating AppRunner service: web

Do you want to integrate this AppRunner service with API Gateway?
This will make the service accessible via API Gateway at /web/*
(y/N): y

✓ Created terraform/apprunner-web.tf
✓ Appended API Gateway integration to terraform/api-gateway.tf
```

**Choose 'y' if:**
- You want the service accessible through API Gateway (`/web/*`)
- You want unified routing with other services
- You want API Gateway features (rate limiting, API keys, etc.)

**Choose 'N' if:**
- You want direct AppRunner URLs only
- You don't need API Gateway features
- You're building a standalone web application

**What this creates:**
- `terraform/apprunner-web.tf` with AppRunner service definition
- API Gateway integration at `/web/*` (if selected)
- Auto-scaling configuration (1-10 instances by default)

### Step 2: Create Backend Application Code

Create the service directory and application files:

```bash
# Create service directory
mkdir -p backend/web

# Copy template from existing service
cp backend/api/main.py backend/web/main.py
cp backend/api/pyproject.toml backend/web/pyproject.toml
```

**Edit `backend/web/main.py`:**

```python
"""Web service - Frontend web application."""

from fastapi import FastAPI
from fastapi.responses import HTMLResponse
import time
import os

# Create FastAPI app
app = FastAPI(
    title="Web Service",
    description="Frontend web application",
    version="1.0.0"
)

# Track service start time
start_time = time.time()

@app.get("/", response_class=HTMLResponse)
async def root():
    """Root endpoint - return HTML."""
    return """
    <!DOCTYPE html>
    <html>
        <head>
            <title>Web Service</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; }
                h1 { color: #333; }
                .info { background: #f0f0f0; padding: 20px; border-radius: 5px; }
            </style>
        </head>
        <body>
            <h1>Web Service</h1>
            <div class="info">
                <p><strong>Service:</strong> Web Frontend</p>
                <p><strong>Version:</strong> 1.0.0</p>
                <p><strong>Status:</strong> Running</p>
            </div>
        </body>
    </html>
    """

@app.get("/health")
async def health():
    """Health check endpoint."""
    uptime = time.time() - start_time
    return {
        "status": "healthy",
        "service": "web",
        "uptime_seconds": round(uptime, 2),
        "port": os.getenv("PORT", "8080")
    }

@app.get("/liveness")
async def liveness():
    """Kubernetes-style liveness probe."""
    return {"status": "alive"}

@app.get("/readiness")
async def readiness():
    """Kubernetes-style readiness probe."""
    return {"status": "ready"}

@app.get("/api/data")
async def get_data():
    """API endpoint for frontend data."""
    return {
        "items": [
            {"id": 1, "name": "Item 1"},
            {"id": 2, "name": "Item 2"},
            {"id": 3, "name": "Item 3"}
        ]
    }

# AppRunner entry point
if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
```

**Edit `backend/web/pyproject.toml`:**

```toml
[project]
name = "web"
version = "1.0.0"
description = "Web frontend service"
requires-python = ">=3.13"
dependencies = [
    "fastapi>=0.115.6",
    "uvicorn>=0.32.1",
    "httpx>=0.27.2",
]

[project.optional-dependencies]
test = [
    "pytest>=8.3.4",
    "pytest-asyncio>=0.24.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

### Step 3: Install Dependencies and Test Locally

```bash
# Navigate to service directory
cd backend/web

# Create virtual environment and install dependencies
uv sync

# Test locally
PORT=8000 uv run python main.py

# In another terminal, test the endpoints
curl http://localhost:8000/health
curl http://localhost:8000/
curl http://localhost:8000/api/data

# Open in browser
open http://localhost:8000/

# Stop the server (Ctrl+C) when done
cd ../..
```

### Step 4: Build and Push Docker Image

```bash
# Build and push to ECR
./scripts/docker-push.sh dev web Dockerfile.apprunner

# Expected output:
# Building Docker image for web service (dev environment)
# Architecture: amd64 (from Dockerfile.apprunner)
# ...
# ✓ Image pushed: <account>.dkr.ecr.us-east-1.amazonaws.com/<project>:web-dev-latest
# ✓ Image pushed: <account>.dkr.ecr.us-east-1.amazonaws.com/<project>:web-dev-2025-11-23-abc1234
```

**What this does:**
- Builds AMD64 image for AppRunner (x86_64 instances)
- Pushes to ECR with versioned tags
- Creates rollback points with datetime tags

### Step 5: Deploy Infrastructure

```bash
# Navigate to Terraform directory
cd terraform

# Review changes
terraform plan -var-file=environments/dev.tfvars

# Apply changes
terraform apply -var-file=environments/dev.tfvars

# Expected output:
# ...
# Plan: 5 to add, 1 to change, 0 to destroy
# ...
# Apply complete! Resources: 5 added, 1 changed, 0 destroyed.
```

**What gets created:**
- AppRunner service: `<project>-dev-web`
- AppRunner auto-scaling config (1-10 instances)
- CloudWatch Log Group: `/aws/apprunner/<project>-dev-web`
- API Gateway integration: `/web/*` (if enabled)
- VPC Connector (if VPC access needed)

**Deployment time:** AppRunner deployments take 3-5 minutes to complete.

### Step 6: Wait for Service to be Ready

```bash
# Check service status
terraform output apprunner_web_status

# Expected output: RUNNING

# If status is OPERATION_IN_PROGRESS, wait a few minutes and check again
```

### Step 7: Test Deployed Service

**Option A: Test via API Gateway (if integrated)**

```bash
# Get API Gateway URL
PRIMARY_URL=$(terraform output -raw primary_endpoint)

# Test web service endpoints
curl $PRIMARY_URL/web/health
curl $PRIMARY_URL/web/
curl $PRIMARY_URL/web/api/data

# Open in browser
echo "$PRIMARY_URL/web/"
```

**Option B: Test via Direct AppRunner URL**

```bash
# Get direct AppRunner URL
APPRUNNER_URL=$(terraform output -raw apprunner_web_url)

# Test endpoints
curl $APPRUNNER_URL/health
curl $APPRUNNER_URL/
curl $APPRUNNER_URL/api/data

# Open in browser
echo "$APPRUNNER_URL"

# Or use make target
cd ..
make test-apprunner-web
```

**Expected responses:**

```json
// GET /web/health or /health
{
  "status": "healthy",
  "service": "web",
  "uptime_seconds": 123.45,
  "port": "8080"
}

// GET /web/ or /
<!DOCTYPE html>
<html>
  <head><title>Web Service</title></head>
  ...
</html>
```

### Step 8: Configure AppRunner Settings (Optional)

Edit `terraform/environments/dev.tfvars` to customize AppRunner:

```hcl
# AppRunner Instance Configuration
apprunner_cpu    = "1024"   # 1 vCPU (256, 512, 1024, 2048, 4096)
apprunner_memory = "2048"   # 2 GB (512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288)
apprunner_port   = 8080     # Port your app listens on

# Auto Scaling
apprunner_min_instances     = 1    # Minimum instances (always running)
apprunner_max_instances     = 10   # Maximum instances
apprunner_max_concurrency   = 100  # Requests per instance before scaling

# Health Check
health_check_path               = "/health"
health_check_interval           = 10   # seconds
health_check_timeout            = 5    # seconds
health_check_healthy_threshold  = 1    # consecutive successes
health_check_unhealthy_threshold = 5   # consecutive failures
```

Reapply after changes:

```bash
cd terraform
terraform apply -var-file=environments/dev.tfvars
```

---

## Integrating AWS Services

Need to add AWS services like SQS, DynamoDB, or S3 to your Lambda or AppRunner services?

See the complete **[AWS Services Integration Guide](AWS-SERVICES-INTEGRATION.md)** for step-by-step instructions on integrating:

- **SQS** - Message queues for async processing
- **DynamoDB** - NoSQL database
- **S3** - Object storage
- **RDS, ElastiCache, SNS** - And many more

The guide includes:
- Complete Terraform modules
- IAM permission templates
- Python code examples with boto3
- Testing procedures
- Best practices and cost optimization

---

## Configuring Service-Specific Variables

Each service can have its own custom configuration for memory, CPU, timeout, and other settings.

### Lambda Service Configuration

Each Lambda function can be configured independently in its Terraform file.

**Edit `terraform/lambda-<service>.tf`:**

```hcl
resource "aws_lambda_function" "worker" {
  function_name = "${var.project_name}-${var.environment}-worker"
  role          = aws_iam_role.lambda_worker.arn

  # Service-specific configuration
  memory_size = 1024        # 1024 MB (default: 512)
  timeout     = 300         # 5 minutes (default: 30)

  # Use arm64 architecture
  architectures = ["arm64"]

  # Reserved concurrency (optional)
  reserved_concurrent_executions = 10  # Limit concurrent executions

  # Environment-specific variables
  environment {
    variables = {
      SERVICE_NAME = "worker"
      LOG_LEVEL    = "INFO"
      # Add more as needed
    }
  }

  # ... rest of configuration
}
```

**Common Lambda Configuration Options:**

| Setting | Values | Use Case |
|---------|--------|----------|
| `memory_size` | 128-10240 MB | More memory = more CPU power |
| `timeout` | 3-900 seconds | Max execution time (API Gateway: 29s) |
| `reserved_concurrent_executions` | 0-1000 | Limit max concurrent invocations |
| `architectures` | `["arm64"]` or `["x86_64"]` | Graviton2 vs x86 |

**Example: High-Memory Data Processing Service**

```hcl
# terraform/lambda-processor.tf
resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-${var.environment}-processor"

  # High memory for data processing
  memory_size = 3008        # 3 GB
  timeout     = 900         # 15 minutes (max)

  # Limit concurrent executions to avoid throttling downstream
  reserved_concurrent_executions = 5

  architectures = ["arm64"]

  # ... rest of configuration
}
```

**Example: Low-Memory Quick API**

```hcl
# terraform/lambda-notifications.tf
resource "aws_lambda_function" "notifications" {
  function_name = "${var.project_name}-${var.environment}-notifications"

  # Minimal resources for quick notifications
  memory_size = 256         # 256 MB
  timeout     = 10          # 10 seconds

  architectures = ["arm64"]

  # ... rest of configuration
}
```

### AppRunner Service Configuration

Each AppRunner service can have different CPU, memory, and scaling settings.

**Edit `terraform/apprunner-<service>.tf`:**

```hcl
resource "aws_apprunner_service" "web" {
  service_name = "${var.project_name}-${var.environment}-web"

  source_configuration {
    image_repository {
      # ... authentication config ...

      image_configuration {
        port = 8080

        # Service-specific resources
        runtime_environment_variables = {
          SERVICE_NAME = "web"
          PORT         = "8080"
        }
      }
    }
  }

  instance_configuration {
    # Service-specific CPU and memory
    cpu    = "1024"  # 1 vCPU
    memory = "2048"  # 2 GB

    instance_role_arn = data.aws_iam_role.apprunner_instance_web.arn
  }

  # Service-specific auto-scaling
  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.web.arn

  # ... rest of configuration
}

# Service-specific auto-scaling configuration
resource "aws_apprunner_auto_scaling_configuration_version" "web" {
  auto_scaling_configuration_name = "${var.project_name}-${var.environment}-web-autoscaling"

  # Web service handles more concurrent requests
  max_concurrency = 200
  max_size        = 10
  min_size        = 2  # Always keep 2 instances warm
}
```

**Common AppRunner Configuration Options:**

| Setting | Values | Use Case |
|---------|--------|----------|
| `cpu` | 256, 512, 1024, 2048, 4096 | 0.25-4 vCPUs |
| `memory` | 512-12288 MB | Must be compatible with CPU |
| `max_concurrency` | 1-200 | Requests per instance before scaling |
| `min_size` | 1-25 | Minimum instances (always running) |
| `max_size` | 1-25 | Maximum instances |

**Valid CPU/Memory Combinations:**

| CPU | Valid Memory (MB) |
|-----|-------------------|
| 256 (0.25 vCPU) | 512, 1024 |
| 512 (0.5 vCPU) | 1024, 2048 |
| 1024 (1 vCPU) | 2048, 3072, 4096 |
| 2048 (2 vCPU) | 4096, 6144, 8192 |
| 4096 (4 vCPU) | 8192, 10240, 12288 |

**Example: High-Traffic Web Service**

```hcl
# terraform/apprunner-api.tf
resource "aws_apprunner_service" "api" {
  service_name = "${var.project_name}-${var.environment}-api"

  instance_configuration {
    cpu    = "2048"  # 2 vCPUs
    memory = "4096"  # 4 GB
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.api.arn
}

resource "aws_apprunner_auto_scaling_configuration_version" "api" {
  auto_scaling_configuration_name = "${var.project_name}-${var.environment}-api-autoscaling"

  max_concurrency = 200  # Handle more requests per instance
  max_size        = 15   # Scale up to 15 instances
  min_size        = 3    # Keep 3 instances warm
}
```

**Example: Low-Traffic Background Worker**

```hcl
# terraform/apprunner-worker.tf
resource "aws_apprunner_service" "worker" {
  service_name = "${var.project_name}-${var.environment}-worker"

  instance_configuration {
    cpu    = "512"   # 0.5 vCPU
    memory = "1024"  # 1 GB
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.worker.arn
}

resource "aws_apprunner_auto_scaling_configuration_version" "worker" {
  auto_scaling_configuration_name = "${var.project_name}-${var.environment}-worker-autoscaling"

  max_concurrency = 50   # Lower concurrency
  max_size        = 3    # Max 3 instances
  min_size        = 1    # Single instance is fine
}
```

### Using Variables for Flexibility

You can also use Terraform variables for more flexibility:

**Create `terraform/variables-services.tf`:**

```hcl
# Service-specific Lambda configurations
variable "lambda_configs" {
  description = "Configuration for each Lambda service"
  type = map(object({
    memory_size = number
    timeout     = number
  }))
  default = {
    api = {
      memory_size = 512
      timeout     = 30
    }
    worker = {
      memory_size = 1024
      timeout     = 300
    }
    processor = {
      memory_size = 3008
      timeout     = 900
    }
  }
}

# Service-specific AppRunner configurations
variable "apprunner_configs" {
  description = "Configuration for each AppRunner service"
  type = map(object({
    cpu             = string
    memory          = string
    min_instances   = number
    max_instances   = number
    max_concurrency = number
  }))
  default = {
    web = {
      cpu             = "1024"
      memory          = "2048"
      min_instances   = 2
      max_instances   = 10
      max_concurrency = 200
    }
    admin = {
      cpu             = "512"
      memory          = "1024"
      min_instances   = 1
      max_instances   = 3
      max_concurrency = 100
    }
  }
}
```

**Use in service file:**

```hcl
# terraform/lambda-worker.tf
resource "aws_lambda_function" "worker" {
  function_name = "${var.project_name}-${var.environment}-worker"

  # Use service-specific config
  memory_size = var.lambda_configs["worker"].memory_size
  timeout     = var.lambda_configs["worker"].timeout

  # ... rest of configuration
}
```

**Override in environment file:**

```hcl
# terraform/environments/prod.tfvars
lambda_configs = {
  api = {
    memory_size = 1024  # More memory in production
    timeout     = 30
  }
  worker = {
    memory_size = 2048  # Even more for worker
    timeout     = 600   # Longer timeout
  }
}
```

### Health Check Configuration

Each service can have custom health check settings:

**For AppRunner services:**

```hcl
# terraform/apprunner-web.tf
resource "aws_apprunner_service" "web" {
  # ... other configuration ...

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 10    # Check every 10 seconds
    timeout             = 5     # 5 second timeout
    healthy_threshold   = 1     # 1 success = healthy
    unhealthy_threshold = 5     # 5 failures = unhealthy
  }
}
```

### Environment-Specific Configuration

You can also vary configuration by environment:

```hcl
# terraform/lambda-api.tf
resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-${var.environment}-api"

  # Conditional configuration based on environment
  memory_size = var.environment == "prod" ? 1024 : 512
  timeout     = var.environment == "prod" ? 60 : 30

  # Production gets reserved concurrency
  reserved_concurrent_executions = var.environment == "prod" ? 100 : null

  # ... rest of configuration
}
```

### Quick Reference: Common Configurations

**Small API (Low Traffic):**
- Lambda: 256-512 MB, 10-30s timeout
- AppRunner: 512 CPU, 1024 MB, 1-3 instances

**Standard API (Medium Traffic):**
- Lambda: 512-1024 MB, 30s timeout
- AppRunner: 1024 CPU, 2048 MB, 2-10 instances

**Data Processing (High Memory):**
- Lambda: 2048-3008 MB, 300-900s timeout
- AppRunner: 2048 CPU, 4096 MB, 1-5 instances

**High-Traffic Web App:**
- AppRunner: 2048 CPU, 4096 MB, 3-15 instances, 200 concurrency

### Testing Configuration Changes

After changing configuration:

```bash
# Plan to see what will change
cd terraform
terraform plan -var-file=environments/dev.tfvars

# Apply changes
terraform apply -var-file=environments/dev.tfvars

# Test the service
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl $PRIMARY_URL/<service>/health
```

### Monitoring Resource Usage

Check if your configuration is appropriate:

```bash
# Lambda: Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=project-dev-worker \
  --start-time 2025-11-23T00:00:00Z \
  --end-time 2025-11-24T00:00:00Z \
  --period 3600 \
  --statistics Maximum,Average

# AppRunner: Check service metrics
aws apprunner describe-service \
  --service-arn $(terraform output -raw apprunner_web_arn) \
  --query 'Service.{Status:Status,CPU:InstanceConfiguration.Cpu,Memory:InstanceConfiguration.Memory}'
```

If you see:
- **High memory usage** → Increase memory_size
- **Timeouts** → Increase timeout
- **Throttling** → Increase reserved_concurrent_executions or max_instances
- **Low utilization** → Decrease resources to save costs

---

## Service Naming Conventions

Follow these conventions for consistency:

### Naming Rules

✅ **Good names:**
- `api` - Main API service
- `worker` - Background jobs
- `scheduler` - Scheduled tasks
- `web` - Web frontend
- `admin` - Admin dashboard
- `notifier` - Notification service

❌ **Avoid:**
- CamelCase: `MyService`
- Spaces: `my service`
- Special characters: `my-service!`
- Generic names: `service1`, `app`

### Path Routing

Services are automatically routed based on name:

| Service Name | Lambda Path | AppRunner Path |
|--------------|-------------|----------------|
| `api` | `/`, `/*` | N/A (first Lambda gets root) |
| `worker` | `/worker/*` | `/worker/*` |
| `scheduler` | `/scheduler/*` | `/scheduler/*` |
| `runner` | N/A | `/runner/*` |
| `web` | N/A | `/web/*` |
| `admin` | N/A | `/admin/*` |

**Important:** Only the **first Lambda service** (typically `api`) gets the root path `/`. All other services use path prefixes.

---

## Testing Your New Service

### Local Testing

```bash
# Lambda service (via Mangum)
cd backend/<service-name>
uv run uvicorn main:app --reload --port 8001

# AppRunner service (direct uvicorn)
cd backend/<service-name>
PORT=8000 uv run python main.py

# Test with curl
curl http://localhost:8000/health
```

### Integration Testing

```bash
# Test via API Gateway
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

# Lambda service
curl $PRIMARY_URL/<service>/health

# AppRunner service
curl $PRIMARY_URL/<service>/health
```

### Load Testing (Optional)

```bash
# Install Apache Bench
# macOS: brew install httpd
# Ubuntu: apt-get install apache2-utils

# Test 1000 requests, 10 concurrent
ab -n 1000 -c 10 "$PRIMARY_URL/<service>/health"
```

### Automated Tests

Create `backend/<service>/tests/test_main.py`:

```python
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_root():
    response = client.get("/")
    assert response.status_code == 200
```

Run tests:

```bash
cd backend/<service>
uv run pytest -v
```

---

## Troubleshooting

### Lambda Service Issues

#### Error: "Function not found"

**Problem:** Lambda function doesn't exist in AWS

**Solution:**
```bash
# Check if Terraform created the function
cd terraform
terraform state list | grep lambda

# If missing, reapply
terraform apply -var-file=environments/dev.tfvars
```

#### Error: "Missing Authentication Token"

**Problem:** API Gateway path not configured correctly

**Solution:**
```bash
# Check path routing in api-gateway.tf
grep -A 5 "path_prefix.*<service>" terraform/api-gateway.tf

# Ensure you're using correct path
curl $PRIMARY_URL/<service>/health  # not just /health
```

#### Error: "Internal Server Error" (500)

**Problem:** Lambda execution error or missing dependencies

**Solution:**
```bash
# Check Lambda logs
aws logs tail /aws/lambda/<project>-dev-<service> --follow

# Common issues:
# 1. Missing dependencies in Docker image
# 2. Import errors in code
# 3. Environment variables not set

# Rebuild image with dependencies
cd backend/<service>
uv sync
cd ../..
./scripts/docker-push.sh dev <service> Dockerfile.lambda
```

#### Cold Start Performance

**Problem:** First request takes 2-3 seconds

**Solution:**
```bash
# This is normal for Lambda cold starts
# To minimize:
# 1. Keep Lambda warm with scheduled pings
# 2. Optimize package size
# 3. Use arm64 architecture (already configured)

# Add CloudWatch Event to keep warm (optional)
# See docs/MONITORING.md for details
```

### AppRunner Service Issues

#### Error: "Service is not ready"

**Problem:** AppRunner still deploying

**Solution:**
```bash
# Check deployment status
terraform output apprunner_<service>_status

# Wait for RUNNING status (3-5 minutes)
# Check logs during deployment
aws logs tail /aws/apprunner/<project>-dev-<service> --follow
```

#### Error: "Failed to reach AppRunner service"

**Problem:** Health check failing or port misconfiguration

**Solution:**
```bash
# Check health endpoint directly
APPRUNNER_URL=$(cd terraform && terraform output -raw apprunner_<service>_url)
curl $APPRUNNER_URL/health

# Verify port configuration
# 1. Check main.py uses PORT environment variable
# 2. Check terraform/environments/dev.tfvars has apprunner_port = 8080
# 3. Ensure Dockerfile.apprunner exposes correct port
```

#### Error: "Service keeps restarting"

**Problem:** Application crash or health check failure

**Solution:**
```bash
# Check logs for errors
aws logs tail /aws/apprunner/<project>-dev-<service> --follow

# Common issues:
# 1. Application not binding to 0.0.0.0
# 2. Port mismatch
# 3. Missing environment variables
# 4. Health check path incorrect

# Fix in main.py:
# uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
```

#### High Costs from Auto-Scaling

**Problem:** AppRunner running too many instances

**Solution:**
```bash
# Adjust auto-scaling in terraform/environments/dev.tfvars
apprunner_min_instances = 1   # Reduce minimum
apprunner_max_instances = 3   # Reduce maximum
apprunner_max_concurrency = 200  # Increase concurrency threshold

# Reapply
cd terraform
terraform apply -var-file=environments/dev.tfvars
```

### General Issues

#### Docker Build Fails

**Problem:** Build errors or missing dependencies

**Solution:**
```bash
# Check Docker is running
docker ps

# Verify Dockerfile exists
ls backend/Dockerfile.lambda
ls backend/Dockerfile.apprunner

# Check for syntax errors in Dockerfile
cat backend/Dockerfile.<type>

# Try building locally
cd backend
docker build -f Dockerfile.<type> -t test-build .
```

#### ECR Push Fails

**Problem:** Authentication or permission issues

**Solution:**
```bash
# Re-authenticate to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  <account>.dkr.ecr.us-east-1.amazonaws.com

# Check ECR repository exists
aws ecr describe-repositories --repository-names <project>

# Check IAM permissions
aws sts get-caller-identity
```

#### Terraform Apply Fails

**Problem:** State locked or resource conflicts

**Solution:**
```bash
# If state is locked
cd terraform
terraform force-unlock <lock-id>

# If resources conflict, import existing resources
terraform import aws_lambda_function.worker <project>-dev-worker

# Or remove from state if orphaned
terraform state rm aws_lambda_function.worker
```

---

## Next Steps

After creating your services:

1. **Set up CI/CD:**
   - Configure GitHub Actions: [GITHUB-ACTIONS.md](GITHUB-ACTIONS.md)
   - Enable automated deployments on push

2. **Add Monitoring:**
   - Set up CloudWatch Alarms: [MONITORING.md](MONITORING.md)
   - Configure X-Ray tracing
   - Create dashboards

3. **Secure Your Services:**
   - Enable API Keys: Set `enable_api_key = true`
   - Add authentication/authorization
   - Configure WAF rules

4. **Optimize Performance:**
   - Tune Lambda memory/timeout settings
   - Adjust AppRunner auto-scaling
   - Implement caching strategies

5. **Add More Services:**
   - Repeat the process for additional services
   - All services share the same API Gateway
   - Each service scales independently

---

## Quick Reference

### Lambda Service Checklist

- [ ] Run `./scripts/setup-terraform-lambda.sh <service>`
- [ ] Create `backend/<service>/main.py`
- [ ] Create `backend/<service>/pyproject.toml`
- [ ] Run `cd backend/<service> && uv sync`
- [ ] Test locally with `uv run uvicorn main:app --reload`
- [ ] Build image: `./scripts/docker-push.sh dev <service> Dockerfile.lambda`
- [ ] Deploy: `cd terraform && terraform apply -var-file=environments/dev.tfvars`
- [ ] Test: `curl $PRIMARY_URL/<service>/health`

### AppRunner Service Checklist

- [ ] Run `./scripts/setup-terraform-apprunner.sh <service>`
- [ ] Choose API Gateway integration (y/N)
- [ ] Create `backend/<service>/main.py`
- [ ] Create `backend/<service>/pyproject.toml`
- [ ] Run `cd backend/<service> && uv sync`
- [ ] Test locally with `PORT=8000 uv run python main.py`
- [ ] Build image: `./scripts/docker-push.sh dev <service> Dockerfile.apprunner`
- [ ] Deploy: `cd terraform && terraform apply -var-file=environments/dev.tfvars`
- [ ] Wait for RUNNING status (3-5 minutes)
- [ ] Test: `curl $PRIMARY_URL/<service>/health`

---

**Last Updated:** 2025-11-23
**Related Documentation:**
- [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md)
- [GitHub Actions CI/CD](GITHUB-ACTIONS.md)
- [API Endpoints](API-ENDPOINTS.md)
- [Troubleshooting](TROUBLESHOOTING-API-GATEWAY.md)
