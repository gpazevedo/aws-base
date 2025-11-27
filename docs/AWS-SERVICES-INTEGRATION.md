# AWS Services Integration Guide

Complete guide for integrating AWS services (SQS, DynamoDB, S3, etc.) with your Lambda and AppRunner services.

---

## Table of Contents

- [Overview](#overview)
- [Architecture Pattern](#architecture-pattern)
- [Adding SQS (Simple Queue Service)](#adding-sqs-simple-queue-service)
- [Adding DynamoDB](#adding-dynamodb)
- [Adding S3 Bucket](#adding-s3-bucket)
- [Quick Reference: Common AWS Services](#quick-reference-common-aws-services)
- [GitHub Actions IAM Permissions](#github-actions-iam-permissions)
- [Best Practices](#best-practices)

---

## Overview

AWS services like SQS, DynamoDB, S3, and RDS can be integrated with your Lambda or AppRunner services to add powerful capabilities:

- **SQS** - Message queues for async processing
- **DynamoDB** - NoSQL database for fast key-value access
- **RDS** - Relational database (PostgreSQL, MySQL, etc.)
- **S3** - Object storage for files, backups, static assets
- **ElastiCache** - Redis/Memcached caching
- **SNS** - Pub/sub messaging and notifications
- **EventBridge** - Event routing and scheduling
- **Secrets Manager** - Secure credential storage
- **Parameter Store** - Configuration management

### Why Integrate AWS Services?

- **Decoupling** - SQS queues decouple services for better resilience
- **Persistence** - DynamoDB and RDS provide durable data storage
- **Scalability** - AWS services scale automatically with your workload
- **Cost-Effective** - Pay only for what you use
- **Managed** - No infrastructure to maintain

---

## Architecture Pattern

```
┌─────────────────────────────────────┐
│  Lambda/AppRunner Service           │
│  ┌─────────────────────────────┐    │
│  │ Application Code            │    │
│  │  ├─ boto3 SDK               │    │
│  │  └─ Environment Variables   │    │
│  └─────────────────────────────┘    │
│           ↓ (IAM permissions)       │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  AWS Service (SQS, DynamoDB, etc.)  │
│  ├─ Managed by AWS                  │
│  ├─ Automatic scaling               │
│  └─ High availability               │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  Service Execution Role             │
│  ├─ Lambda execution role           │
│  └─ AppRunner instance role         │
└─────────────────────────────────────┘
```

### Integration Steps (General)

1. **Create Infrastructure** - Define AWS service with Terraform
2. **Grant IAM Permissions** - Allow service to access AWS resource
3. **Set Environment Variables** - Pass resource identifiers to application
4. **Update Application Code** - Use boto3 SDK to interact with AWS service
5. **Deploy and Test** - Verify integration works correctly

---

## Adding SQS (Simple Queue Service)

**Use case:** Asynchronous job processing, decoupling services, event-driven architectures

**Benefits:**

- Decouple services for better resilience
- Handle traffic spikes with buffering
- Reliable message delivery with retries
- Dead Letter Queue for failed messages

### Step 1: Create SQS Terraform Module

Create `terraform/modules/sqs-queue/main.tf`:

```hcl
# SQS Queue Module
variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev, test, prod)"
  type        = string
}

variable "queue_name" {
  description = "Queue name"
  type        = string
}

variable "visibility_timeout" {
  description = "Visibility timeout in seconds"
  type        = number
  default     = 30
}

variable "message_retention" {
  description = "Message retention in seconds (1-14 days)"
  type        = number
  default     = 345600  # 4 days
}

# Main Queue
resource "aws_sqs_queue" "queue" {
  name                       = "${var.project_name}-${var.environment}-${var.queue_name}"
  visibility_timeout_seconds = var.visibility_timeout
  message_retention_seconds  = var.message_retention
  receive_wait_time_seconds  = 20  # Long polling

  # Dead Letter Queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.queue_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                       = "${var.project_name}-${var.environment}-${var.queue_name}-dlq"
  message_retention_seconds  = 1209600  # 14 days

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.queue_name}-dlq"
    Environment = var.environment
    Project     = var.project_name
  }
}

output "queue_url" {
  description = "Queue URL"
  value       = aws_sqs_queue.queue.url
}

output "queue_arn" {
  description = "Queue ARN"
  value       = aws_sqs_queue.queue.arn
}

output "dlq_url" {
  description = "Dead Letter Queue URL"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "Dead Letter Queue ARN"
  value       = aws_sqs_queue.dlq.arn
}
```

### Step 2: Add Queue to Your Service

Create `terraform/sqs-jobs.tf`:

```hcl
# Job Queue for Worker Service
module "jobs_queue" {
  source = "./modules/sqs-queue"

  project_name        = var.project_name
  environment         = var.environment
  queue_name          = "jobs"
  visibility_timeout  = 300  # 5 minutes (match Lambda timeout)
  message_retention   = 345600  # 4 days
}

# Output for application use
output "jobs_queue_url" {
  description = "Jobs queue URL"
  value       = module.jobs_queue.queue_url
}

output "jobs_queue_arn" {
  description = "Jobs queue ARN"
  value       = module.jobs_queue.queue_arn
}
```

### Step 3: Grant IAM Permissions

**For Lambda**, edit `terraform/lambda-worker.tf`:

```hcl
# Add SQS permissions to Lambda execution role
resource "aws_iam_role_policy" "worker_sqs" {
  name = "${var.project_name}-${var.environment}-worker-sqs"
  role = aws_iam_role.lambda_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          module.jobs_queue.queue_arn,
          module.jobs_queue.dlq_arn
        ]
      }
    ]
  })
}
```

**For AppRunner**, edit `terraform/apprunner-worker.tf`:

```hcl
# Add SQS permissions to AppRunner instance role
resource "aws_iam_role_policy" "apprunner_worker_sqs" {
  name = "${var.project_name}-${var.environment}-apprunner-worker-sqs"
  role = data.aws_iam_role.apprunner_instance_worker.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = module.jobs_queue.queue_arn
      }
    ]
  })
}
```

### Step 4: Update Application Code

Edit `backend/worker/main.py` to add SQS integration with structured logging and OpenTelemetry tracing:

```python
"""Worker service with SQS integration."""

import json
from typing import Any

import boto3
import structlog
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from opentelemetry.instrumentation.boto3sqs import Boto3SQSInstrumentor
from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict

# =============================================================================
# Configuration
# =============================================================================

logger = structlog.get_logger()


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # AWS configuration
    aws_region: str = "us-east-1"
    jobs_queue_url: str = ""

    # Service configuration
    service_name: str = "worker"
    environment: str = "dev"


settings = Settings()

# =============================================================================
# Application
# =============================================================================

app = FastAPI(title="Worker Service")

# Initialize SQS client with OpenTelemetry instrumentation
Boto3SQSInstrumentor().instrument()
sqs = boto3.client("sqs", region_name=settings.aws_region)


class JobData(BaseModel):
    """Job data model."""

    job_type: str = "default"
    data: dict[str, Any]


@app.post("/jobs")
async def create_job(job: JobData) -> dict[str, Any]:
    """Send job to SQS queue with structured logging and distributed tracing."""
    if not settings.jobs_queue_url:
        logger.error("sqs_queue_not_configured", service=settings.service_name)
        raise HTTPException(status_code=500, detail="Queue URL not configured")

    try:
        logger.info(
            "sqs_send_message_attempt",
            queue_url=settings.jobs_queue_url,
            job_type=job.job_type,
        )

        response = sqs.send_message(
            QueueUrl=settings.jobs_queue_url,
            MessageBody=json.dumps(job.data),
            MessageAttributes={"JobType": {"StringValue": job.job_type, "DataType": "String"}},
        )

        logger.info("sqs_message_sent", message_id=response["MessageId"], job_type=job.job_type)

        return {
            "message": "Job queued successfully",
            "message_id": response["MessageId"],
            "job_type": job.job_type,
        }

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        error_message = e.response.get("Error", {}).get("Message", str(e))
        logger.error("sqs_send_message_failed", error_code=error_code, job_type=job.job_type)
        raise HTTPException(status_code=500, detail=f"Failed to queue job: {error_message}") from e


@app.get("/jobs/process")
async def process_jobs() -> dict[str, Any]:
    """Process jobs from SQS queue with structured logging."""
    if not settings.jobs_queue_url:
        logger.error("sqs_queue_not_configured", service=settings.service_name)
        raise HTTPException(status_code=500, detail="Queue URL not configured")

    try:
        logger.info("sqs_receive_messages_attempt", queue_url=settings.jobs_queue_url)

        # Receive messages (long polling for cost efficiency)
        response = sqs.receive_message(
            QueueUrl=settings.jobs_queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=20,
            MessageAttributeNames=["All"],
        )

        messages = response.get("Messages", [])
        processed = []

        logger.info("sqs_messages_received", message_count=len(messages))

        for message in messages:
            try:
                body = json.loads(message["Body"])
                job_type = (
                    message.get("MessageAttributes", {}).get("JobType", {}).get("StringValue", "unknown")
                )

                logger.info("processing_job", message_id=message["MessageId"], job_type=job_type)

                # Your processing logic here
                result = {"status": "processed", "data": body, "job_type": job_type}
                processed.append(result)

                # Delete message from queue after successful processing
                sqs.delete_message(
                    QueueUrl=settings.jobs_queue_url,
                    ReceiptHandle=message["ReceiptHandle"],
                )

                logger.info("job_processed_success", message_id=message["MessageId"], job_type=job_type)

            except Exception as e:
                logger.error(
                    "job_processing_failed",
                    error=str(e),
                    message_id=message.get("MessageId"),
                )
                # Message stays in queue for retry or moves to DLQ after max retries

        return {"processed": len(processed), "results": processed}

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        logger.error("sqs_receive_messages_failed", error_code=error_code)
        raise HTTPException(status_code=500, detail=f"Failed to process jobs: {error_code}") from e
```

**Key Features:**

- ✅ Structured logging with structlog for JSON logs
- ✅ OpenTelemetry instrumentation for distributed tracing
- ✅ Pydantic Settings for configuration management
- ✅ Type hints for better code quality
- ✅ Proper error handling with ClientError
- ✅ Long polling (20 seconds) for cost efficiency

### Step 5: Add boto3 Dependencies

The dependencies are already included in `backend/worker/pyproject.toml` if created using the setup script. Verify these lines exist:

```toml
[project]
dependencies = [
    # ... other dependencies ...
    "boto3>=1.35.0,<2.0.0",
    "botocore>=1.35.0,<2.0.0",
    "opentelemetry-instrumentation-boto3sqs>=0.48b0,<1.0.0",  # For SQS tracing
    "structlog>=24.4.0,<25.0.0",  # Structured logging
]
```

### Step 6: Set Environment Variable

**For Lambda**, edit `terraform/lambda-worker.tf`:

```hcl
resource "aws_lambda_function" "worker" {
  # ... existing configuration ...

  environment {
    variables = {
      JOBS_QUEUE_URL = module.jobs_queue.queue_url
      AWS_REGION     = var.aws_region
    }
  }
}
```

**For AppRunner**, edit `terraform/apprunner-worker.tf`:

```hcl
resource "aws_apprunner_service" "worker" {
  # ... existing configuration ...

  source_configuration {
    image_repository {
      # ... existing configuration ...

      image_configuration {
        port = var.apprunner_port

        runtime_environment_variables = {
          JOBS_QUEUE_URL = module.jobs_queue.queue_url
          AWS_REGION     = var.aws_region
        }
      }
    }
  }
}
```

### Step 7: Deploy and Test

```bash
# Deploy infrastructure
cd terraform
terraform apply -var-file=environments/dev.tfvars

# Get queue URL
QUEUE_URL=$(terraform output -raw jobs_queue_url)
echo "Queue URL: $QUEUE_URL"

# Test sending job
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl -X POST $PRIMARY_URL/worker/jobs \
  -H "Content-Type: application/json" \
  -d '{"type": "process_data", "payload": {"key": "value"}}'

# Test processing jobs
curl $PRIMARY_URL/worker/jobs/process
```

---

## Adding DynamoDB

**Use case:** NoSQL database for fast key-value access, high-throughput applications

**Benefits:**
- Single-digit millisecond latency
- Automatic scaling with pay-per-request pricing
- Built-in replication and backups
- Global tables for multi-region deployments

### Step 1: Create DynamoDB Terraform Module

Create `terraform/modules/dynamodb-table/main.tf`:

```hcl
# DynamoDB Table Module
variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "table_name" {
  description = "Table name"
  type        = string
}

variable "hash_key" {
  description = "Hash key attribute name"
  type        = string
  default     = "id"
}

variable "range_key" {
  description = "Range key attribute name (optional)"
  type        = string
  default     = null
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

resource "aws_dynamodb_table" "table" {
  name           = "${var.project_name}-${var.environment}-${var.table_name}"
  billing_mode   = var.billing_mode
  hash_key       = var.hash_key
  range_key      = var.range_key

  attribute {
    name = var.hash_key
    type = "S"
  }

  dynamic "attribute" {
    for_each = var.range_key != null ? [1] : []
    content {
      name = var.range_key
      type = "S"
    }
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.table_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

output "table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.table.name
}

output "table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.table.arn
}
```

### Step 2: Add Table to Your Service

Create `terraform/dynamodb-users.tf`:

```hcl
# Users Table
module "users_table" {
  source = "./modules/dynamodb-table"

  project_name  = var.project_name
  environment   = var.environment
  table_name    = "users"
  hash_key      = "user_id"
  range_key     = "created_at"
  billing_mode  = "PAY_PER_REQUEST"  # On-demand pricing
}

output "users_table_name" {
  description = "Users table name"
  value       = module.users_table.table_name
}
```

### Step 3: Grant IAM Permissions

Edit `terraform/lambda-api.tf`:

```hcl
# Add DynamoDB permissions
resource "aws_iam_role_policy" "api_dynamodb" {
  name = "${var.project_name}-${var.environment}-api-dynamodb"
  role = aws_iam_role.lambda_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = module.users_table.table_arn
      }
    ]
  })
}
```

### Step 4: Update Application Code

Add DynamoDB integration to your service with structured logging and OpenTelemetry. Here's an example for `backend/api/main.py`:

```python
"""API service with DynamoDB integration."""

from datetime import UTC, datetime
from typing import Any

import boto3
import structlog
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr
from pydantic_settings import BaseSettings, SettingsConfigDict

# =============================================================================
# Configuration
# =============================================================================

logger = structlog.get_logger()


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # AWS configuration
    aws_region: str = "us-east-1"
    users_table_name: str = ""

    # Service configuration
    service_name: str = "api"
    environment: str = "dev"


settings = Settings()

# =============================================================================
# Application
# =============================================================================

app = FastAPI(title="API Service")

# Initialize DynamoDB resource
# Note: boto3 resource automatically gets OpenTelemetry instrumentation
# when opentelemetry-instrumentation-boto3sqs is installed
dynamodb = boto3.resource("dynamodb", region_name=settings.aws_region)
table = dynamodb.Table(settings.users_table_name) if settings.users_table_name else None


class User(BaseModel):
    """User data model with validation."""

    user_id: str
    name: str
    email: EmailStr


class UserResponse(BaseModel):
    """User response model."""

    user_id: str
    name: str
    email: str
    created_at: str


@app.post("/users", response_model=UserResponse)
async def create_user(user: User) -> dict[str, Any]:
    """Create a new user in DynamoDB with structured logging."""
    if not table:
        logger.error("dynamodb_table_not_configured", service=settings.service_name)
        raise HTTPException(status_code=500, detail="Table not configured")

    try:
        logger.info(
            "dynamodb_put_item_attempt",
            table_name=settings.users_table_name,
            user_id=user.user_id,
        )

        item = {
            "user_id": user.user_id,
            "name": user.name,
            "email": user.email,
            "created_at": datetime.now(UTC).isoformat(),
        }

        table.put_item(Item=item)

        logger.info("dynamodb_user_created", user_id=user.user_id)

        return item

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        logger.error(
            "dynamodb_put_item_failed",
            error_code=error_code,
            user_id=user.user_id,
        )
        raise HTTPException(status_code=500, detail=f"Failed to create user: {error_code}") from e


@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: str) -> dict[str, Any]:
    """Get user from DynamoDB with structured logging."""
    if not table:
        logger.error("dynamodb_table_not_configured", service=settings.service_name)
        raise HTTPException(status_code=500, detail="Table not configured")

    try:
        logger.info("dynamodb_get_item_attempt", user_id=user_id)

        response = table.get_item(Key={"user_id": user_id})

        if "Item" not in response:
            logger.warning("dynamodb_user_not_found", user_id=user_id)
            raise HTTPException(status_code=404, detail="User not found")

        logger.info("dynamodb_user_retrieved", user_id=user_id)

        return response["Item"]

    except HTTPException:
        raise
    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        logger.error("dynamodb_get_item_failed", error_code=error_code, user_id=user_id)
        raise HTTPException(status_code=500, detail=f"Failed to get user: {error_code}") from e


@app.get("/users")
async def list_users() -> dict[str, Any]:
    """List all users with pagination support."""
    if not table:
        logger.error("dynamodb_table_not_configured", service=settings.service_name)
        raise HTTPException(status_code=500, detail="Table not configured")

    try:
        logger.info("dynamodb_scan_attempt", table_name=settings.users_table_name)

        # Note: scan() is inefficient for large tables. Use query() or pagination instead.
        response = table.scan()

        users = response.get("Items", [])
        logger.info("dynamodb_scan_success", user_count=len(users))

        return {"users": users, "count": len(users)}

    except ClientError as e:
        error_code = e.response.get("Error", {}).get("Code", "Unknown")
        logger.error("dynamodb_scan_failed", error_code=error_code)
        raise HTTPException(status_code=500, detail=f"Failed to list users: {error_code}") from e

handler = Mangum(app, lifespan="off")
```

**Key Features:**

- ✅ Structured logging with structlog for JSON logs
- ✅ OpenTelemetry instrumentation for boto3 (automatic when package installed)
- ✅ Pydantic Settings for configuration management
- ✅ Type hints and response models for API documentation
- ✅ Proper error handling with ClientError and specific error codes
- ✅ Email validation with Pydantic EmailStr
- ✅ UTC timezone-aware timestamps

### Step 5: Set Environment Variable

Edit `terraform/lambda-api.tf`:

```hcl
resource "aws_lambda_function" "api" {
  # ... existing configuration ...

  environment {
    variables = {
      USERS_TABLE_NAME = module.users_table.table_name
      AWS_REGION       = var.aws_region
    }
  }
}
```

### Step 6: Deploy and Test

```bash
# Deploy
cd terraform
terraform apply -var-file=environments/dev.tfvars

# Test
PRIMARY_URL=$(terraform output -raw primary_endpoint)

# Create user
curl -X POST $PRIMARY_URL/users \
  -H "Content-Type: application/json" \
  -d '{"user_id": "user-123", "name": "John Doe", "email": "john@example.com"}'

# Get user
curl $PRIMARY_URL/users/user-123

# List users
curl $PRIMARY_URL/users
```

---

## Adding S3 Bucket

**Use case:** File storage, static assets, backups, data lakes

**Benefits:**

- Unlimited storage capacity
- 99.999999999% (11 9's) durability
- Versioning and lifecycle policies
- Integration with CloudFront CDN

### Quick Setup

Create `terraform/s3-storage.tf`:

```hcl
# Storage Bucket
resource "aws_s3_bucket" "storage" {
  bucket = "${var.project_name}-${var.environment}-storage"

  tags = {
    Name        = "${var.project_name}-${var.environment}-storage"
    Environment = var.environment
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "storage" {
  bucket = aws_s3_bucket.storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "storage" {
  bucket = aws_s3_bucket.storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "storage_bucket_name" {
  value = aws_s3_bucket.storage.id
}
```

Grant permissions in your service:

```hcl
resource "aws_iam_role_policy" "api_s3" {
  name = "${var.project_name}-${var.environment}-api-s3"
  role = aws_iam_role.lambda_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.storage.arn,
          "${aws_s3_bucket.storage.arn}/*"
        ]
      }
    ]
  })
}
```

---

## Quick Reference: Common AWS Services

| Service | Use Case | Module Path | IAM Actions | Cost Model |
|---------|----------|-------------|-------------|------------|
| **SQS** | Message queues | `modules/sqs-queue` | `sqs:SendMessage`, `sqs:ReceiveMessage` | $0.40/million requests |
| **DynamoDB** | NoSQL database | `modules/dynamodb-table` | `dynamodb:PutItem`, `dynamodb:GetItem` | Pay per request |
| **S3** | Object storage | Built-in `aws_s3_bucket` | `s3:PutObject`, `s3:GetObject` | $0.023/GB/month |
| **RDS** | SQL database | `modules/rds-instance` | Via VPC security groups | ~$15/month (db.t4g.micro) |
| **ElastiCache** | Redis/Memcached | `modules/elasticache-cluster` | Via VPC security groups | ~$13/month (cache.t4g.micro) |
| **SNS** | Pub/sub messaging | Built-in `aws_sns_topic` | `sns:Publish`, `sns:Subscribe` | $0.50/million publishes |
| **Secrets Manager** | Secret storage | Built-in `aws_secretsmanager_secret` | `secretsmanager:GetSecretValue` | $0.40/secret/month |
| **Parameter Store** | Configuration | Built-in `aws_ssm_parameter` | `ssm:GetParameter` | Free (standard) |

---

## GitHub Actions IAM Permissions

**Critical:** When adding AWS services to your infrastructure, you need TWO layers of IAM permissions:

1. **Service Execution Roles** - Allow Lambda/AppRunner to ACCESS the AWS services (documented in each service section above)
2. **GitHub Actions Deployment Roles** - Allow Terraform to CREATE/MANAGE the AWS services (documented below)

This section covers the GitHub Actions deployment permissions required for Terraform to create and manage AWS services.

---

### Understanding the Two Permission Layers

```text
┌─────────────────────────────────────────────────────────┐
│  GitHub Actions (CI/CD Pipeline)                        │
│  ├─ Uses: GitHub Actions IAM Role                       │
│  ├─ Purpose: Deploy infrastructure with Terraform       │
│  └─ Needs: Permissions to CREATE AWS services           │
└─────────────────────────────────────────────────────────┘
                        ↓ (creates)
┌─────────────────────────────────────────────────────────┐
│  AWS Services (SQS, DynamoDB, S3, etc.)                 │
│  ├─ Created by: Terraform via GitHub Actions            │
│  └─ Accessed by: Lambda/AppRunner services              │
└─────────────────────────────────────────────────────────┘
                        ↓ (accessed by)
┌─────────────────────────────────────────────────────────┐
│  Lambda/AppRunner Service                               │
│  ├─ Uses: Service Execution Role                        │
│  ├─ Purpose: Run application code                       │
│  └─ Needs: Permissions to ACCESS AWS services           │
└─────────────────────────────────────────────────────────┘
```

**Key Difference:**

- **Service execution roles** need read/write access to use the services (e.g., `sqs:SendMessage`, `dynamodb:PutItem`)
- **GitHub Actions roles** need management permissions to create/update/delete the services (e.g., `sqs:CreateQueue`, `dynamodb:CreateTable`)

---

### Where to Add GitHub Actions Permissions

GitHub Actions IAM policies are defined in the **bootstrap infrastructure**, not the application terraform.

**Location:** `bootstrap/` directory

- `bootstrap/main.tf` - Base policies attached to all environment roles
- `bootstrap/lambda.tf` - Lambda-specific deployment policies
- `bootstrap/apprunner.tf` - App Runner-specific deployment policies

**Roles that need these permissions:**

- `${project_name}-github-actions-dev` - Development environment
- `${project_name}-github-actions-test` - Test environment (if enabled)
- `${project_name}-github-actions-prod` - Production environment

---

### Adding SQS Management Permissions

To allow GitHub Actions to create and manage SQS queues, add this policy to `bootstrap/main.tf`:

```hcl
# =============================================================================
# SQS Management Policy for GitHub Actions
# =============================================================================

resource "aws_iam_policy" "sqs_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  name        = "${var.project_name}-sqs-management"
  description = "Allows GitHub Actions to manage SQS queues for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # SQS Queue Management
      {
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:SetQueueAttributes",
          "sqs:ListQueues",
          "sqs:TagQueue",
          "sqs:UntagQueue",
          "sqs:ListQueueTags",
          "sqs:PurgeQueue"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:${local.account_id}:${var.project_name}-*"
      },
      # List all queues (required for terraform state reconciliation)
      {
        Effect = "Allow"
        Action = [
          "sqs:ListQueues"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach to dev role
resource "aws_iam_role_policy_attachment" "dev_sqs_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.sqs_management[0].arn
}

# Attach to test role
resource "aws_iam_role_policy_attachment" "test_sqs_management" {
  count = (var.enable_lambda || var.enable_apprunner) && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.sqs_management[0].arn
}

# Attach to prod role
resource "aws_iam_role_policy_attachment" "prod_sqs_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.sqs_management[0].arn
}
```

---

### Adding DynamoDB Management Permissions

To allow GitHub Actions to create and manage DynamoDB tables:

```hcl
# =============================================================================
# DynamoDB Management Policy for GitHub Actions
# =============================================================================

resource "aws_iam_policy" "dynamodb_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  name        = "${var.project_name}-dynamodb-management"
  description = "Allows GitHub Actions to manage DynamoDB tables for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB Table Management
      {
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:ListTables",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:UpdateContinuousBackups"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${var.project_name}-*"
      },
      # Global Secondary Index Management
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${var.project_name}-*/index/*"
      },
      # List all tables (required for terraform state reconciliation)
      {
        Effect = "Allow"
        Action = [
          "dynamodb:ListTables"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach to dev role
resource "aws_iam_role_policy_attachment" "dev_dynamodb_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.dynamodb_management[0].arn
}

# Attach to test role
resource "aws_iam_role_policy_attachment" "test_dynamodb_management" {
  count = (var.enable_lambda || var.enable_apprunner) && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.dynamodb_management[0].arn
}

# Attach to prod role
resource "aws_iam_role_policy_attachment" "prod_dynamodb_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.dynamodb_management[0].arn
}
```

---

### Adding S3 Management Permissions

To allow GitHub Actions to create and manage S3 buckets:

```hcl
# =============================================================================
# S3 Management Policy for GitHub Actions
# =============================================================================

resource "aws_iam_policy" "s3_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  name        = "${var.project_name}-s3-management"
  description = "Allows GitHub Actions to manage S3 buckets for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Bucket Management
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketCORS",
          "s3:PutBucketCORS",
          "s3:DeleteBucketCORS",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:DeleteLifecycleConfiguration",
          "s3:GetBucketLogging",
          "s3:PutBucketLogging"
        ]
        Resource = "arn:aws:s3:::${var.project_name}-*"
      },
      # List all buckets (required for terraform state reconciliation)
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach to dev role
resource "aws_iam_role_policy_attachment" "dev_s3_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_dev.name
  policy_arn = aws_iam_policy.s3_management[0].arn
}

# Attach to test role
resource "aws_iam_role_policy_attachment" "test_s3_management" {
  count = (var.enable_lambda || var.enable_apprunner) && var.enable_test_environment ? 1 : 0

  role       = aws_iam_role.github_actions_test[0].name
  policy_arn = aws_iam_policy.s3_management[0].arn
}

# Attach to prod role
resource "aws_iam_role_policy_attachment" "prod_s3_management" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  role       = aws_iam_role.github_actions_prod.name
  policy_arn = aws_iam_policy.s3_management[0].arn
}
```

---

### Quick Reference: GitHub Actions Permissions by Service

| AWS Service | Key Actions Required | Resource Pattern |
|-------------|---------------------|------------------|
| **SQS** | `sqs:CreateQueue`, `sqs:DeleteQueue`, `sqs:SetQueueAttributes` | `arn:aws:sqs:*:*:${project_name}-*` |
| **DynamoDB** | `dynamodb:CreateTable`, `dynamodb:DeleteTable`, `dynamodb:UpdateTable` | `arn:aws:dynamodb:*:*:table/${project_name}-*` |
| **S3** | `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutBucket*` | `arn:aws:s3:::${project_name}-*` |
| **SNS** | `sns:CreateTopic`, `sns:DeleteTopic`, `sns:SetTopicAttributes` | `arn:aws:sns:*:*:${project_name}-*` |
| **Secrets Manager** | `secretsmanager:CreateSecret`, `secretsmanager:DeleteSecret` | `arn:aws:secretsmanager:*:*:secret:${project_name}-*` |
| **EventBridge** | `events:PutRule`, `events:DeleteRule`, `events:PutTargets` | `arn:aws:events:*:*:rule/${project_name}-*` |
| **RDS** | `rds:CreateDBInstance`, `rds:DeleteDBInstance`, `rds:ModifyDBInstance` | `arn:aws:rds:*:*:db:${project_name}-*` |
| **ElastiCache** | `elasticache:CreateCacheCluster`, `elasticache:DeleteCacheCluster` | `arn:aws:elasticache:*:*:cluster:${project_name}-*` |

---

### Deployment Workflow

1. **Add IAM policies to bootstrap**

   ```bash
   cd bootstrap
   # Edit main.tf to add the AWS service management policies
   # Add policy resources and role attachments
   ```

2. **Apply bootstrap changes**

   ```bash
   make bootstrap-apply
   # This updates the GitHub Actions IAM roles with new permissions
   ```

3. **Add AWS service to application terraform**

   ```bash
   # Create terraform/modules/sqs-queue/main.tf (or DynamoDB, S3, etc.)
   # Reference the module in terraform/main.tf
   ```

4. **Deploy via GitHub Actions**

   ```bash
   git add .
   git commit -m "Add SQS queue for async processing"
   git push
   # GitHub Actions will now have permissions to create the SQS queue
   ```

---

### Common Errors and Solutions

#### Error: "User is not authorized to perform: sqs:CreateQueue"

**Cause:** GitHub Actions role doesn't have SQS management permissions

**Solution:** Add the SQS management policy to `bootstrap/main.tf` and run `make bootstrap-apply`

#### Error: "User is not authorized to perform: dynamodb:CreateTable"

**Cause:** GitHub Actions role doesn't have DynamoDB management permissions

**Solution:** Add the DynamoDB management policy to `bootstrap/main.tf` and run `make bootstrap-apply`

#### Error: "Access Denied" when creating S3 bucket

**Cause:** GitHub Actions role doesn't have S3 management permissions

**Solution:** Add the S3 management policy to `bootstrap/main.tf` and run `make bootstrap-apply`

---

### Best Practices for GitHub Actions IAM

1. **Use Resource Constraints**
   - Limit permissions to resources with your project name prefix
   - Example: `arn:aws:sqs:*:*:${var.project_name}-*`

2. **Separate Bootstrap from Application**
   - AWS service management policies go in `bootstrap/`
   - Service execution policies go in application `terraform/`

3. **Apply Least Privilege**
   - Only add permissions for AWS services you actually use
   - Remove unused policies to reduce attack surface

4. **Test in Dev First**
   - Always test new AWS service integrations in dev environment
   - Verify GitHub Actions can create/update/delete resources

5. **Document Custom Permissions**
   - If you add custom AWS services, document the required permissions
   - Include both GitHub Actions and service execution permissions

---

## Best Practices

### 1. Use Modules for Reusability

Create Terraform modules for common AWS services:

```hcl
# terraform/modules/sqs-queue/
# terraform/modules/dynamodb-table/
# terraform/modules/s3-bucket/
```

Benefits:
- Consistent configuration across environments
- Easy to update and maintain
- Testable infrastructure components

### 2. Implement Least Privilege IAM

Grant only the permissions required for the specific use case:

```hcl
# ❌ BAD: Too permissive
Action = ["dynamodb:*"]

# ✅ GOOD: Specific actions
Action = [
  "dynamodb:PutItem",
  "dynamodb:GetItem",
  "dynamodb:Query"
]
```

### 3. Use Environment Variables

Pass resource identifiers via environment variables:

```hcl
environment {
  variables = {
    QUEUE_URL = module.jobs_queue.queue_url
    TABLE_NAME = module.users_table.table_name
    BUCKET_NAME = aws_s3_bucket.storage.id
    AWS_REGION = var.aws_region
  }
}
```

### 4. Enable Encryption

Always enable encryption at rest:

```hcl
# DynamoDB
server_side_encryption {
  enabled = true
}

# S3
server_side_encryption_configuration {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# SQS
kms_master_key_id = aws_kms_key.queue.id
```

### 5. Implement Monitoring

Enable CloudWatch logging for AWS services:

```hcl
# SQS Alarms
resource "aws_cloudwatch_metric_alarm" "queue_age" {
  alarm_name          = "queue-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "300"  # 5 minutes
}
```

### 6. Use VPC Endpoints (Production)

For production environments, use VPC endpoints for private access:

```hcl
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"
  route_table_ids = [aws_route_table.private.id]
}
```

Benefits:
- Traffic stays within AWS network
- No internet gateway required
- Improved security and performance

### 7. Test Locally with LocalStack

Test AWS service integration locally before deploying:

```bash
# Install LocalStack
pip install localstack

# Start LocalStack
localstack start

# Configure boto3 to use LocalStack
export AWS_ENDPOINT_URL=http://localhost:4566
```

### 8. Implement Backups

Enable automatic backups for critical data:

```hcl
# DynamoDB Point-in-Time Recovery
point_in_time_recovery {
  enabled = true
}

# S3 Versioning
versioning_configuration {
  status = "Enabled"
}
```

### 9. Cost Optimization

- **DynamoDB**: Use on-demand billing for variable workloads, provisioned for predictable traffic
- **SQS**: Enable long polling (20 seconds) to reduce API calls
- **S3**: Implement lifecycle policies to transition old objects to cheaper storage classes

```hcl
# S3 Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  rule {
    id     = "archive-old-files"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}
```

### 10. Tag Resources

Use consistent tagging for cost tracking and organization:

```hcl
tags = {
  Name        = "${var.project_name}-${var.environment}-${var.resource_name}"
  Environment = var.environment
  Project     = var.project_name
  ManagedBy   = "Terraform"
  CostCenter  = "engineering"
}
```

---

## Additional Resources

- [AWS SDK for Python (Boto3) Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [SQS Best Practices](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-best-practices.html)
- [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

---

**Last Updated:** 2025-11-27
**Related Documentation:**

- [Adding Services Guide](ADDING-SERVICES.md)
- [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md)
- [Terraform Bootstrap](TERRAFORM-BOOTSTRAP.md)
