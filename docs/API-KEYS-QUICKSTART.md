# API Keys Quick Start

**5-minute guide to using per-service API keys**

---

## For Developers: Using API Keys in Code

### 1. Install Shared Library

```bash
cd backend/your-service
uv add --editable ../shared
```

### 2. Use ServiceAPIClient

```python
from shared.api_client import ServiceAPIClient, get_service_url

# Initialize with your service name
client = ServiceAPIClient(service_name="api")

# Call another service (API key auto-injected)
async def call_other_service():
    url = get_service_url("runner")
    response = await client.get(f"{url}/health")
    return response.json()

# Clean up when done
await client.aclose()
```

### 3. Context Manager (Recommended)

```python
async def fetch_embedding(text: str):
    async with ServiceAPIClient(service_name="api") as client:
        url = get_service_url("s3vector")
        response = await client.post(
            f"{url}/embeddings/generate",
            json={"text": text}
        )
        return response.json()
```

**That's it!** The client handles:

- ✅ Retrieving API key from Secrets Manager
- ✅ Caching for performance
- ✅ Adding `x-api-key` header
- ✅ Connection pooling

---

## For DevOps: Terraform Setup

### Quick Setup (Automated)

The setup scripts automatically generate all API key infrastructure:

**For Lambda services:**

```bash
./scripts/setup-terraform-lambda.sh <service-name>
```

**For App Runner services:**

```bash
./scripts/setup-terraform-apprunner.sh <service-name>
```

These scripts automatically create:

- ✅ Service API key configuration
- ✅ Secrets Manager IAM policy
- ✅ Required environment variables (PROJECT_NAME, ENVIRONMENT, API_GATEWAY_URL, AWS_REGION)

### Enable API Keys

In `terraform/environments/dev.tfvars`:

```hcl
enable_service_api_keys = true
```

### Customize API Key Quotas (Optional)

Each service's API key configuration is defined in its Terraform file (e.g., `lambda-api.tf` or `apprunner-runner.tf`):

```hcl
locals {
  api_service_api_key = var.enable_service_api_keys ? {
    api = {
      quota_limit  = 100000  # ← Adjust as needed
      quota_period = "MONTH"
      description  = "API service"
    }
  } : {}
}
```

### Deploy

```bash
cd terraform
terraform init
terraform apply -var-file=environments/dev.tfvars
```

After deployment, retrieve your API keys:

```bash
# Get all API keys
terraform output -json service_api_key_values

# Get specific service key
terraform output -json service_api_key_values | jq -r '.api'
```

---

## Manual Configuration (Advanced)

If you need to manually configure API keys or customize the setup:

### 1. Define Service API Key

In your service's Terraform file (e.g., `lambda-api.tf`):

```hcl
locals {
  api_service_api_key = var.enable_service_api_keys ? {
    api = {
      quota_limit  = 100000
      quota_period = "MONTH"
      description  = "API service"
    }
  } : {}
}
```

### 2. Grant Secrets Manager Access

**For Lambda services:**

```hcl
resource "aws_iam_role_policy" "api_secrets_access" {
  count = var.enable_service_api_keys ? 1 : 0

  name = "${var.project_name}-${var.environment}-api-secrets"
  role = data.aws_iam_role.lambda_execution_api.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}/${var.environment}/api/api-key-*"]
    }]
  })
}
```

**For App Runner services:**

```hcl
resource "aws_iam_role_policy" "runner_secrets_access" {
  count = var.enable_service_api_keys ? 1 : 0

  name = "${var.project_name}-${var.environment}-runner-secrets"
  role = data.aws_iam_role.apprunner_instance_runner.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}/${var.environment}/runner/api-key-*"]
    }]
  })
}
```

### 3. Add Environment Variables

**For Lambda:**

```hcl
resource "aws_lambda_function" "api" {
  environment {
    variables = {
      ENVIRONMENT     = var.environment
      PROJECT_NAME    = var.project_name
      SERVICE_NAME    = "api"
      API_GATEWAY_URL = local.api_gateway_enabled ? module.api_gateway_shared[0].invoke_url : ""
    }
  }
}
```

**For App Runner:**

```hcl
resource "aws_apprunner_service" "runner" {
  source_configuration {
    image_repository {
      image_configuration {
        runtime_environment_variables = {
          ENVIRONMENT     = var.environment
          PROJECT_NAME    = var.project_name
          SERVICE_NAME    = "runner"
          API_GATEWAY_URL = local.api_gateway_enabled ? module.api_gateway_shared[0].invoke_url : ""
        }
      }
    }
  }
}
```

---

## Common Patterns

### Calling S3Vector from API Service

```python
# backend/api/main.py
from shared.api_client import ServiceAPIClient, get_service_url

client = ServiceAPIClient(service_name="api")

@app.post("/analyze")
async def analyze_text(text: str):
    s3vector_url = get_service_url("s3vector")

    response = await client.post(
        f"{s3vector_url}/embeddings/generate",
        json={"text": text, "store_in_s3": False}
    )

    return response.json()
```

### Calling API from Runner Service

```python
# backend/runner/main.py
from shared.api_client import ServiceAPIClient, get_service_url

client = ServiceAPIClient(service_name="runner")

@app.get("/api-health")
async def check_api_health():
    api_url = get_service_url("api")
    response = await client.get(f"{api_url}/health")
    return response.json()
```

### Error Handling

```python
import httpx

async def safe_call():
    async with ServiceAPIClient(service_name="api") as client:
        try:
            url = get_service_url("runner")
            response = await client.get(f"{url}/health")
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 403:
                # API key authentication failed
                logger.error("api_key_auth_failed")
            raise
        except httpx.RequestError as e:
            # Network/connection error
            logger.error("service_unreachable", error=str(e))
            raise
```

---

## Environment Variables

Required in all services:

```bash
PROJECT_NAME=fin-advisor      # Project name
ENVIRONMENT=dev               # Environment (dev/test/prod)
API_GATEWAY_URL=https://...   # API Gateway base URL
AWS_REGION=us-east-1          # AWS region
```

---

## Troubleshooting

### ❌ "API key not found in Secrets Manager"

**Fix**: Ensure `enable_service_api_keys = true` and run `terraform apply`

### ❌ "403 Forbidden"

**Possible causes**:

1. Wrong API key → Check Secrets Manager
2. Missing IAM permissions → Add Secrets Manager policy
3. Method doesn't require API key → Set `api_key_required = true` in Terraform

**Debug**:

```bash
# Check if secret exists
aws secretsmanager list-secrets | grep "api-key"

# Get API key value
aws secretsmanager get-secret-value \
  --secret-id fin-advisor/dev/api/api-key \
  --query SecretString --output text

# Test with curl
curl -H "x-api-key: $API_KEY" "$API_GATEWAY_URL/runner/health"
```

### ❌ "429 Too Many Requests"

**Fix**: Increase quota in service configuration:

```hcl
quota_limit = 200000  # Was 100000
```

---

## Reference Commands

```bash
# Get all API keys
terraform output -json service_api_key_values

# Get specific service key
terraform output -json service_api_key_values | jq -r '.api'

# List all secrets
aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `api-key`)].Name'

# Rotate key (force recreation)
terraform taint 'module.api_gateway_shared.aws_api_gateway_api_key.service_keys["api"]'
terraform apply
```

---

## Next Steps

📖 **Full Documentation**: See [PER-SERVICE-API-KEYS.md](PER-SERVICE-API-KEYS.md)

🏗️ **Architecture Guide**: See [MULTI-SERVICE-ARCHITECTURE.md](MULTI-SERVICE-ARCHITECTURE.md)
