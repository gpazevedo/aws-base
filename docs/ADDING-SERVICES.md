# Adding New Services

This guide explains how to add new Lambda and App Runner services using the provided automation scripts.

## ✅ Prerequisites

- Bootstrap infrastructure deployed (`make bootstrap-apply`)
- `uv` installed for Python package management
- Docker installed and running

---

## ⚡ Adding a Lambda Service

Lambda is best for APIs, event processing, and scheduled tasks.

### 1. Generate Infrastructure
Use the helper script to generate the Terraform configuration and API Gateway integration:

```bash
# Syntax: ./scripts/setup-terraform-lambda.sh <service-name> [enable_api_key]
./scripts/setup-terraform-lambda.sh worker true
```

**What happens:**
- Creates `terraform/lambda-worker.tf` (Lambda function definition).
- Appends integration to `terraform/api-gateway.tf` (routing `/worker/*` to this Lambda).

### 2. Create Application Code
Create your service directory in `backend/<service-name>`:

```bash
mkdir -p backend/worker
cp backend/api/main.py backend/worker/main.py
cp backend/api/pyproject.toml backend/worker/pyproject.toml
```

### 3. Deploy
Build the image and apply Terraform changes:

```bash
# 1. Build & Push (automatically builds arm64)
./scripts/docker-push.sh dev worker Dockerfile.lambda

# 2. Deploy
cd terraform
terraform apply -var-file=environments/dev.tfvars
```

### 4. Test
```bash
# Get API URL
PRIMARY_URL=$(terraform output -raw primary_endpoint)

# Test endpoint
curl $PRIMARY_URL/worker/health
```

---

## 🏃 Adding an App Runner Service

App Runner is best for long-running web apps, WebSockets, or high-concurrency services.

### 1. Generate Infrastructure
```bash
# Syntax: ./scripts/setup-terraform-apprunner.sh <service-name>
./scripts/setup-terraform-apprunner.sh web
```

**Prompts:**
- **Integrate with API Gateway?** (y/n): Choose 'y' to route `/web/*` through the main API Gateway, or 'n' for a standalone URL.

### 2. Create Application Code
Same as Lambda, but use `Dockerfile.apprunner` for building.

### 3. Deploy
```bash
# 1. Build & Push (automatically builds amd64)
./scripts/docker-push.sh dev web Dockerfile.apprunner

# 2. Deploy
cd terraform
terraform apply -var-file=environments/dev.tfvars
```

---

## ⚙️ Configuration

### Service Settings
Edit the generated `.tf` files to customize:
- **Memory/CPU**: `memory_size` (Lambda) or `instance_configuration` (App Runner).
- **Timeout**: `timeout` (Lambda).
- **Environment Variables**: Add to the `environment` block.

### Adding AWS Resources
To add SQS, DynamoDB, or S3, see [AWS-SERVICES-INTEGRATION.md](AWS-SERVICES-INTEGRATION.md).

---

## 🔍 Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues with deployments, Docker builds, and API Gateway.
