# Per-Service API Keys Guide

This document explains how to set up and use individual API keys for each service to enable secure inter-service communication.

---

## 📚 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Setup Instructions](#setup-instructions)
- [Using API Keys in Services](#using-api-keys-in-services)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

Each service (API, Runner, S3Vector, etc.) has its own dedicated API key that allows it to:

1. **Authenticate** when calling other services through API Gateway
2. **Track usage** individually per service
3. **Set quotas** specific to each service's needs
4. **Rotate keys** independently without affecting other services

### Benefits

- **Security**: Each service has minimal access with its own credentials
- **Monitoring**: Track which service is making how many requests
- **Quotas**: Set different rate limits per service based on usage patterns
- **Isolation**: Compromised key affects only one service
- **Auditability**: Clear attribution of API calls to specific services

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                         API Gateway                             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Shared REST API                                         │   │
│  │  • /api/*      → API Lambda                              │   │
│  │  │  /runner/*   → Runner AppRunner                       │   │
│  │  • /s3vector/* → S3Vector Lambda                         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Per-Service API Keys                                    │   │
│  │  • api-service-key       → Usage Plan A (100k/month)     │   │
│  │  • runner-service-key    → Usage Plan B (50k/month)      │   │
│  │  • s3vector-service-key  → Usage Plan C (200k/month)     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                   AWS Secrets Manager                           │
│  • {project}/{env}/api/api-key      = "abc123..."               │
│  • {project}/{env}/runner/api-key   = "def456..."               │
│  • {project}/{env}/s3vector/api-key = "ghi789..."               │
└─────────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Service Code                                 │
│  ServiceAPIClient reads API key from Secrets Manager            │
│  and injects it automatically in all requests                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup Instructions

### Step 1: Define Service API Keys in Terraform

In each service's Terraform file (e.g., `terraform/lambda-api.tf`), add the API key configuration:

```hcl
# terraform/lambda-api.tf

# Define API key configuration for this service
locals {
  api_service_api_key = var.enable_service_api_keys ? {
    api = {
      quota_limit  = 100000         # 100k requests per month
      quota_period = "MONTH"
      description  = "API service - handles main API endpoints"
    }
  } : {}
}
```

For AppRunner services (`terraform/apprunner-runner.tf`):

```hcl
# terraform/apprunner-runner.tf

# Define API key configuration for this service
locals {
  runner_service_api_key = var.enable_service_api_keys ? {
    runner = {
      quota_limit  = 50000          # 50k requests per month
      quota_period = "MONTH"
      description  = "Runner service - processes background tasks"
    }
  } : {}
}
```

### Step 2: Pass Configuration to API Gateway Module

Update the API Gateway module call to include service API keys:

```hcl
# terraform/api-gateway.tf

module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"

  # ... existing configuration ...

  # Merge all service API keys
  service_api_keys = merge(
    local.api_service_api_key,
    local.runner_service_api_key,
    local.s3vector_service_api_key,
    # Add more services here
  )
}
```

### Step 3: Grant Secrets Manager Access to Services

Each Lambda function or AppRunner service needs permission to read its API key:

```hcl
# terraform/lambda-api.tf

# IAM policy for Secrets Manager access
resource "aws_iam_role_policy" "api_secrets_access" {
  name = "${var.project_name}-${var.environment}-api-secrets-access"
  role = aws_iam_role.api_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          # Allow access to this service's API key
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/api/api-key-*"
        ]
      }
    ]
  })
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}
```

### Step 4: Set Environment Variables

Add the API Gateway URL to each service's environment:

```hcl
# terraform/lambda-api.tf

resource "aws_lambda_function" "api" {
  # ... existing configuration ...

  environment {
    variables = {
      PROJECT_NAME     = var.project_name
      ENVIRONMENT      = var.environment
      API_GATEWAY_URL  = module.api_gateway_shared[0].invoke_url
      # ... other variables ...
    }
  }
}
```

### Step 5: Deploy

```bash
cd terraform
terraform apply
```

This will:

1. Create API keys for each service
2. Store keys in AWS Secrets Manager
3. Create usage plans with quotas
4. Grant services access to their keys

---

## Using API Keys in Services

### Option 1: Using ServiceAPIClient (Recommended)

The shared library provides a ready-to-use client:

```python
# In your service code (e.g., backend/api/main.py)
from shared.api_client import ServiceAPIClient, get_service_url

# Initialize client with your service name
api_client = ServiceAPIClient(service_name="api")

# Call another service
async def call_runner_service():
    """Call the runner service's health endpoint."""
    runner_url = get_service_url("runner")  # Auto-builds URL

    # API key is automatically injected
    response = await api_client.get(f"{runner_url}/health")

    return response.json()

# Call s3vector service
async def generate_embedding(text: str):
    """Generate embedding using s3vector service."""
    s3vector_url = get_service_url("s3vector")

    response = await api_client.post(
        f"{s3vector_url}/embeddings/generate",
        json={"text": text}
    )

    return response.json()

# Remember to close the client
await api_client.aclose()
```

### Option 2: Context Manager (Automatic Cleanup)

```python
from shared.api_client import ServiceAPIClient, get_service_url

async def call_service():
    # Client is automatically closed when exiting the context
    async with ServiceAPIClient(service_name="api") as client:
        runner_url = get_service_url("runner")
        response = await client.get(f"{runner_url}/health")
        return response.json()
```

### Option 3: Manual API Key Retrieval

If you need the raw API key:

```python
from shared.api_client import ServiceAPIClient

client = ServiceAPIClient(service_name="api")
api_key = client.get_api_key()

# Use with your own HTTP client
import httpx
async with httpx.AsyncClient() as http_client:
    response = await http_client.get(
        "https://api-gateway.amazonaws.com/runner/health",
        headers={"x-api-key": api_key}
    )
```

### Integration Example: API Service Calling S3Vector

```python
# backend/api/main.py

from shared.api_client import ServiceAPIClient, get_service_url
from fastapi import FastAPI

app = FastAPI()

# Initialize service client
service_client = ServiceAPIClient(service_name="api")

@app.post("/generate-embedding")
async def generate_embedding(text: str):
    """
    Generate embedding by calling the s3vector service.

    The API key is automatically injected by ServiceAPIClient.
    """
    try:
        s3vector_url = get_service_url("s3vector")

        # Call s3vector service with authentication
        response = await service_client.post(
            f"{s3vector_url}/embeddings/generate",
            json={
                "text": text,
                "store_in_s3": False
            }
        )

        response.raise_for_status()
        return response.json()

    except httpx.HTTPStatusError as e:
        if e.response.status_code == 403:
            raise HTTPException(
                status_code=500,
                detail="API key authentication failed. Check Secrets Manager configuration."
            )
        raise

# Clean up on shutdown
@app.on_event("shutdown")
async def shutdown():
    await service_client.aclose()
```

---

## Retrieving API Keys

### Get All Service API Keys

```bash
cd terraform

# Get all API key values (sensitive output)
terraform output -json service_api_key_values

# Get specific service key
terraform output -json service_api_key_values | jq -r '.api'
terraform output -json service_api_key_values | jq -r '.runner'
terraform output -json service_api_key_values | jq -r '.s3vector'
```

### Get API Key from Secrets Manager

```bash
# Using AWS CLI
aws secretsmanager get-secret-value \
  --secret-id fin-advisor/dev/api/api-key \
  --query SecretString \
  --output text

# Store in environment variable
export API_SERVICE_KEY=$(aws secretsmanager get-secret-value \
  --secret-id fin-advisor/dev/api/api-key \
  --query SecretString \
  --output text)
```

### Test with curl

```bash
# Get the API key
API_KEY=$(terraform output -json service_api_key_values | jq -r '.api')

# Get API Gateway URL
API_URL=$(terraform output -raw primary_endpoint)

# Make authenticated request
curl -H "x-api-key: $API_KEY" "$API_URL/runner/health"
```

---

## Security Best Practices

### 1. Principle of Least Privilege

Each service should only have access to **its own** API key:

```hcl
# ✅ GOOD: Service can only read its own key
Resource = [
  "arn:aws:secretsmanager:region:account:secret:project/env/api/api-key-*"
]

# ❌ BAD: Service can read all keys
Resource = [
  "arn:aws:secretsmanager:region:account:secret:project/env/*/api-key-*"
]
```

### 2. Enable API Key Caching

API keys are cached by default to minimize Secrets Manager calls:

```python
# Caching is enabled by default
client = ServiceAPIClient(service_name="api", cache_api_key=True)

# Invalidate cache after key rotation
client.invalidate_api_key_cache()
```

### 3. Monitor Usage

Set up CloudWatch alarms for unusual API key usage:

```hcl
resource "aws_cloudwatch_metric_alarm" "api_key_usage" {
  alarm_name          = "${var.project_name}-${var.environment}-api-high-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Count"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10000"  # Alert if >10k requests in 5 minutes

  dimensions = {
    ApiName = "${var.project_name}-${var.environment}-api"
    ApiKeyId = module.api_gateway_shared.service_api_key_ids["api"]
  }
}
```

### 4. Rotate API Keys Regularly

```bash
# Force recreation of a specific service's API key
terraform taint 'module.api_gateway_shared.aws_api_gateway_api_key.service_keys["api"]'
terraform apply

# The service will automatically pick up the new key on next request
# (if caching is enabled, invalidate the cache or restart the service)
```

### 5. Use HTTPS Only

API keys should **never** be sent over unencrypted HTTP:

```python
# ✅ GOOD: HTTPS
response = await client.get("https://api-gateway.amazonaws.com/...")

# ❌ BAD: HTTP (never do this)
response = await client.get("http://api-gateway.amazonaws.com/...")
```

---

## Troubleshooting

### API Key Not Found

**Error**: `ResourceNotFoundException: Secrets Manager can't find the specified secret`

**Solution**:

1. Verify `enable_service_api_keys = true` in Terraform
2. Run `terraform apply` to create the secrets
3. Check the secret exists:

   ```bash
   aws secretsmanager list-secrets | grep api-key
   ```

### 403 Forbidden

**Error**: API Gateway returns 403 when calling another service

**Possible causes**:

1. API key is not being sent: Check `x-api-key` header
2. Wrong API key: Verify the key matches Secrets Manager
3. API key not associated with usage plan: Check Terraform configuration
4. API Gateway method doesn't require API key: Set `api_key_required = true`

**Debug**:

```bash
# Test with known good API key
API_KEY=$(terraform output -json service_api_key_values | jq -r '.api')
curl -v -H "x-api-key: $API_KEY" "$API_URL/runner/health"

# Check API Gateway logs
aws logs tail /aws/apigateway/fin-advisor-dev --follow
```

### Quota Exceeded

**Error**: `429 Too Many Requests`

**Solution**:

1. Check current usage:

   ```bash
   aws apigateway get-usage \
     --usage-plan-id <plan-id> \
     --key-id <key-id> \
     --start-date 2025-01-01 \
     --end-date 2025-01-31
   ```

2. Increase quota in service configuration:

   ```hcl
   quota_limit = 200000  # Increase from 100000
   ```

3. Apply changes:

   ```bash
   terraform apply
   ```

### Cached Key After Rotation

**Issue**: Service still using old API key after rotation

**Solution**:

```python
# Option 1: Invalidate cache programmatically
client.invalidate_api_key_cache()

# Option 2: Disable caching temporarily
client = ServiceAPIClient(service_name="api", cache_api_key=False)

# Option 3: Restart the service (Lambda warm containers, AppRunner instances)
```

---

## Example: Complete Multi-Service Setup

### Service Definitions

```hcl
# terraform/lambda-api.tf
locals {
  api_service_api_key = var.enable_service_api_keys ? {
    api = {
      quota_limit  = 100000
      quota_period = "MONTH"
      description  = "API service"
    }
  } : {}
}

# terraform/apprunner-runner.tf
locals {
  runner_service_api_key = var.enable_service_api_keys ? {
    runner = {
      quota_limit  = 50000
      quota_period = "MONTH"
      description  = "Runner service"
    }
  } : {}
}

# terraform/lambda-s3vector.tf
locals {
  s3vector_service_api_key = var.enable_service_api_keys ? {
    s3vector = {
      quota_limit  = 200000
      quota_period = "MONTH"
      description  = "S3Vector service"
    }
  } : {}
}
```

### API Gateway Configuration

```hcl
# terraform/api-gateway.tf
module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"

  # Merge all service API keys
  service_api_keys = merge(
    local.api_service_api_key,
    local.runner_service_api_key,
    local.s3vector_service_api_key,
  )

  # ... rest of configuration ...
}
```

### Usage Example

```python
# backend/runner/main.py
from shared.api_client import ServiceAPIClient, get_service_url

# Runner service calling S3Vector service
runner_client = ServiceAPIClient(service_name="runner")

@app.post("/process-text")
async def process_text(text: str):
    # Call s3vector to generate embedding
    s3vector_url = get_service_url("s3vector")
    embedding_response = await runner_client.post(
        f"{s3vector_url}/embeddings/generate",
        json={"text": text}
    )

    # Process the embedding
    embedding = embedding_response.json()["embedding"]

    return {"status": "processed", "dimension": len(embedding)}
```

---

## Next Steps

1. ✅ **Define API keys** for each service in their Terraform files
2. ✅ **Grant Secrets Manager access** to each service
3. ✅ **Use ServiceAPIClient** in your service code
4. ✅ **Monitor usage** with CloudWatch metrics
5. ✅ **Set up alerts** for quota limits
6. ✅ **Rotate keys** periodically

For more information, see:

- [API Endpoints Documentation](API-ENDPOINTS.md)
- [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md)
- [Service Configuration](SERVICE-CONFIGURATION.md)
