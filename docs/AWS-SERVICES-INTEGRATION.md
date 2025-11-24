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
│  ┌─────────────────────────────┐   │
│  │ Application Code            │   │
│  │  ├─ boto3 SDK               │   │
│  │  └─ Environment Variables   │   │
│  └─────────────────────────────┘   │
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

Edit `backend/worker/main.py`:

```python
"""Worker service with SQS integration."""

import os
import json
import boto3
from fastapi import FastAPI, HTTPException
from mangum import Mangum

app = FastAPI(title="Worker Service")

# Initialize SQS client
sqs = boto3.client('sqs', region_name=os.getenv('AWS_REGION', 'us-east-1'))
QUEUE_URL = os.getenv('JOBS_QUEUE_URL')

@app.post("/jobs")
async def create_job(job_data: dict):
    """Send job to SQS queue."""
    if not QUEUE_URL:
        raise HTTPException(status_code=500, detail="Queue URL not configured")

    try:
        response = sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(job_data),
            MessageAttributes={
                'JobType': {
                    'StringValue': job_data.get('type', 'default'),
                    'DataType': 'String'
                }
            }
        )

        return {
            "message": "Job queued successfully",
            "message_id": response['MessageId'],
            "data": job_data
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to queue job: {str(e)}")

@app.get("/jobs/process")
async def process_jobs():
    """Process jobs from SQS queue."""
    if not QUEUE_URL:
        raise HTTPException(status_code=500, detail="Queue URL not configured")

    try:
        # Receive messages (long polling)
        response = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=20,
            MessageAttributeNames=['All']
        )

        messages = response.get('Messages', [])
        processed = []

        for message in messages:
            # Process message
            body = json.loads(message['Body'])

            # Your processing logic here
            result = {"status": "processed", "data": body}
            processed.append(result)

            # Delete message from queue
            sqs.delete_message(
                QueueUrl=QUEUE_URL,
                ReceiptHandle=message['ReceiptHandle']
            )

        return {
            "processed": len(processed),
            "results": processed
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to process jobs: {str(e)}")

handler = Mangum(app, lifespan="off")
```

### Step 5: Add boto3 Dependency

Edit `backend/worker/pyproject.toml`:

```toml
[project]
dependencies = [
    "fastapi>=0.115.6",
    "mangum>=0.19.0",
    "boto3>=1.35.0",  # Add boto3
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

Edit `backend/api/main.py`:

```python
"""API service with DynamoDB integration."""

import os
import boto3
from datetime import datetime
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from mangum import Mangum

app = FastAPI(title="API Service")

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb', region_name=os.getenv('AWS_REGION', 'us-east-1'))
table_name = os.getenv('USERS_TABLE_NAME')
table = dynamodb.Table(table_name) if table_name else None

class User(BaseModel):
    user_id: str
    name: str
    email: str

@app.post("/users")
async def create_user(user: User):
    """Create a new user in DynamoDB."""
    if not table:
        raise HTTPException(status_code=500, detail="Table not configured")

    try:
        item = {
            'user_id': user.user_id,
            'name': user.name,
            'email': user.email,
            'created_at': datetime.utcnow().isoformat()
        }

        table.put_item(Item=item)

        return {"message": "User created", "user": item}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/users/{user_id}")
async def get_user(user_id: str):
    """Get user from DynamoDB."""
    if not table:
        raise HTTPException(status_code=500, detail="Table not configured")

    try:
        response = table.get_item(Key={'user_id': user_id})

        if 'Item' not in response:
            raise HTTPException(status_code=404, detail="User not found")

        return response['Item']
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/users")
async def list_users():
    """List all users."""
    if not table:
        raise HTTPException(status_code=500, detail="Table not configured")

    try:
        response = table.scan()
        return {"users": response.get('Items', [])}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

handler = Mangum(app, lifespan="off")
```

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

**Last Updated:** 2025-11-23
**Related Documentation:**
- [Adding Services Guide](ADDING-SERVICES.md)
- [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md)
- [Terraform Bootstrap](TERRAFORM-BOOTSTRAP.md)
