# Multi-Service Architecture Guide

This document describes the multi-service architecture implementation with API Gateway path-based routing for Lambda and AppRunner services.

---

## Overview

The infrastructure supports deploying multiple Lambda and AppRunner services behind a single API Gateway using path-based routing. This provides a unified entry point while maintaining service isolation.

## Architecture

```
API Gateway (Single Entry Point)
├── / (root)           → Lambda 'api' service
├── /{proxy+}          → Lambda 'api' service
├── /worker/*          → Lambda 'worker' service
├── /scheduler/*       → Lambda 'scheduler' service
├── /apprunner/*       → AppRunner 'apprunner' service
├── /web/*             → AppRunner 'web' service
└── /admin/*           → AppRunner 'admin' service
```

### Path Routing Strategy

**Lambda Services:**
- **First service** (`api`): Gets root path (`/`, `/{proxy+}`)
  - Handles: `/`, `/health`, `/greet`, `/docs`, etc.
- **Additional services**: Get path prefix matching service name
  - `/worker/*` → worker service
  - `/scheduler/*` → scheduler service

**AppRunner Services:**
- All AppRunner services use path prefix
  - `/apprunner/*` → apprunner service
  - `/web/*` → web service
  - `/admin/*` → admin service

## Terraform Structure

```
terraform/
├── api-gateway.tf                           # Main orchestration file
│   ├── module "api_gateway_shared"         # Shared gateway resources
│   ├── module "api_gateway_lambda_api"     # Lambda 'api' integration
│   ├── module "api_gateway_lambda_worker"  # Lambda 'worker' integration
│   └── module "api_gateway_apprunner_*"    # AppRunner integrations
├── lambda-api.tf                            # Lambda 'api' service
├── lambda-worker.tf                         # Lambda 'worker' service
├── apprunner-apprunner.tf                   # AppRunner 'apprunner' service
└── modules/
    ├── api-gateway-shared/                  # Shared API Gateway module
    ├── api-gateway-lambda-integration/      # Lambda integration module
    └── api-gateway-apprunner-integration/   # AppRunner integration module
```

## Setup Scripts

### Lambda Services

```bash
# Create first Lambda service (gets root path)
./scripts/setup-terraform-lambda.sh api false

# Create additional Lambda services (get path prefix)
./scripts/setup-terraform-lambda.sh worker
./scripts/setup-terraform-lambda.sh scheduler
```

**What the script does:**
1. Creates `lambda-{service}.tf` with Lambda function definition
2. On first run: Creates `api-gateway.tf` with shared module
3. On subsequent runs: Appends integration module to `api-gateway.tf`
4. Sets `path_prefix=""` for 'api', `path_prefix="{service}"` for others

### AppRunner Services

```bash
# Create AppRunner services
./scripts/setup-terraform-apprunner.sh apprunner
./scripts/setup-terraform-apprunner.sh web
./scripts/setup-terraform-apprunner.sh admin

# When prompted:
# y = Add to API Gateway (path-based routing)
# N = Direct access only (no API Gateway integration)
```

**What the script does:**
1. Creates `apprunner-{service}.tf` with AppRunner service definition
2. Optionally appends AppRunner integration to `api-gateway.tf`
3. Always sets `path_prefix="{service}"` for AppRunner services

## Deployment Workflow

### 1. Deploy Bootstrap (One-time)

```bash
# Enable AppRunner support
vim bootstrap/terraform.tfvars
# Set: enable_apprunner = true

# Apply bootstrap
cd bootstrap
terraform apply
```

### 2. Create Services

```bash
# Lambda services
./scripts/setup-terraform-lambda.sh api false
./scripts/setup-terraform-lambda.sh worker

# AppRunner services
./scripts/setup-terraform-apprunner.sh apprunner  # Answer 'y' to API Gateway prompt
```

### 3. Build and Push Images

```bash
# Lambda images (arm64)
./scripts/docker-push.sh dev api Dockerfile.lambda
./scripts/docker-push.sh dev worker Dockerfile.lambda

# AppRunner images (amd64)
./scripts/docker-push.sh dev apprunner Dockerfile.apprunner
```

### 4. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply -var-file=environments/dev.tfvars
```

## Testing

### Get API Gateway URL

```bash
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)
echo $PRIMARY_URL
# Output: https://abc123.execute-api.us-east-1.amazonaws.com/dev
```

### Test Lambda Services

```bash
# 'api' service (root path)
curl $PRIMARY_URL/health
curl "$PRIMARY_URL/greet?name=World"
curl $PRIMARY_URL/docs

# 'worker' service (path prefix)
curl $PRIMARY_URL/worker/health
curl $PRIMARY_URL/worker/jobs

# Or use make targets
make test-lambda-api
make test-lambda-worker
```

### Test AppRunner Services

```bash
# 'apprunner' service (path prefix)
curl $PRIMARY_URL/apprunner/health
curl "$PRIMARY_URL/apprunner/greet?name=Claude"

# 'web' service (path prefix)
curl $PRIMARY_URL/web/health

# Or use make targets
make test-apprunner-apprunner
make test-apprunner-web
```

### Direct AppRunner Access

AppRunner services also have direct URLs (bypassing API Gateway):

```bash
# Get direct URL
APPRUNNER_URL=$(cd terraform && terraform output -raw apprunner_apprunner_url)

# Test directly
curl $APPRUNNER_URL/health
```

## Configuration

### API Gateway Settings

In `terraform/environments/{env}.tfvars`:

```hcl
# Enable API Gateway
enable_api_gateway_standard = true
enable_direct_access        = false  # Disable direct Lambda URLs in production

# Rate Limiting
api_throttle_burst_limit = 5000
api_throttle_rate_limit  = 10000

# Logging
api_log_retention_days = 7
api_logging_level      = "INFO"
enable_xray_tracing    = true

# API Key (optional)
enable_api_key = false
```

### AppRunner Settings

In `terraform/variables.tf`:

```hcl
# Instance Configuration
apprunner_port   = 8080
apprunner_cpu    = "1024"  # 1 vCPU
apprunner_memory = "2048"  # 2 GB

# Auto Scaling
apprunner_min_instances  = 1
apprunner_max_instances  = 10
apprunner_max_concurrency = 100

# Health Check
health_check_path = "/health"
health_check_interval = 10
health_check_timeout  = 5
```

## Module Architecture

### Shared API Gateway Module

**Location:** `terraform/modules/api-gateway-shared/`

**Purpose:** Creates shared API Gateway resources used by all services

**Resources:**
- REST API
- Deployment & Stage
- CloudWatch Logs
- Method Settings (throttling, logging)
- API Keys & Usage Plans (optional)

**Outputs:**
- `api_id` - REST API ID
- `root_resource_id` - Root resource ID
- `execution_arn` - Execution ARN for permissions
- `invoke_url` - API Gateway endpoint URL

### Lambda Integration Module

**Location:** `terraform/modules/api-gateway-lambda-integration/`

**Purpose:** Creates AWS_PROXY integration for Lambda functions

**Resources:**
- API Gateway Resources (`/{service}`, `/{service}/{proxy+}`)
- Methods (ANY)
- Integrations (AWS_PROXY to Lambda)
- Lambda Permissions

**Parameters:**
- `service_name` - Service identifier
- `path_prefix` - Path prefix ("" for root, "service" for `/service/*`)
- `lambda_function_name` - Lambda function to integrate
- `enable_root_method` - Allow handling root path (only for 'api')

### AppRunner Integration Module

**Location:** `terraform/modules/api-gateway-apprunner-integration/`

**Purpose:** Creates HTTP_PROXY integration for AppRunner services

**Resources:**
- API Gateway Resources (`/{service}`, `/{service}/{proxy+}`)
- Methods (ANY)
- Integrations (HTTP_PROXY to AppRunner)

**Parameters:**
- `service_name` - Service identifier
- `path_prefix` - Path prefix (always set for AppRunner)
- `apprunner_service_url` - AppRunner service URL
- `enable_root_method` - Usually false for AppRunner

## Integration Dependencies

API Gateway deployment depends on all integrations being created first. This is handled through:

```hcl
# In api-gateway.tf
module "api_gateway_shared" {
  # ...
  integration_ids = compact([
    try(module.api_gateway_lambda_api[0].integration_id, ""),
    try(module.api_gateway_lambda_worker[0].integration_id, ""),
    try(module.api_gateway_apprunner_apprunner[0].integration_id, "")
  ])
}
```

The `integration_ids` parameter creates implicit dependencies, ensuring integrations are created before deployment.

## Benefits

1. **Single Entry Point:** One API Gateway URL for all services
2. **Service Isolation:** Each service has its own infrastructure file
3. **Path-Based Routing:** Clear URL structure (`/service/path`)
4. **Modular:** Easy to add/remove services
5. **Idempotent:** Scripts can run multiple times safely
6. **Scalable:** Supports unlimited Lambda and AppRunner services
7. **Cost-Effective:** Single API Gateway shared across services

## Limitations

1. **Path Conflicts:** Service names must be unique
2. **Root Path:** Only one service can handle root path (typically 'api')
3. **API Gateway Limits:** 300 resources per API (rarely hit in practice)
4. **Cold Starts:** Lambda functions may have cold start delays
5. **Timeout:** API Gateway has 29-second timeout

## Best Practices

1. **Use 'api' for root path:** Reserve root path for main API service
2. **Consistent naming:** Use lowercase, hyphen-separated service names
3. **Health endpoints:** All services should have `/health` endpoint
4. **Path structure:** Keep service-specific paths under service prefix
5. **Documentation:** Update API-ENDPOINTS.md when adding services
6. **Testing:** Test each service individually and through API Gateway

## Troubleshooting

### Path Not Found

**Issue:** `{"message": "Missing Authentication Token"}`

**Solution:** Check path routing - AppRunner services need `/apprunner/path` not `/path`

### Integration Circular Dependency

**Issue:** `Error: Cycle: module.api_gateway_shared`

**Solution:** Use `integration_ids` parameter instead of explicit `depends_on`

### AppRunner Connection Failed

**Issue:** `{"detail": "Failed to reach AppRunner service"}`

**Solution:**
1. Verify AppRunner service is running: `terraform output apprunner_*_status`
2. Check health endpoint directly: `curl $(terraform output -raw apprunner_*_url)/health`
3. Verify path includes service prefix: `/apprunner/health` not `/health`

## Resources

- [API Gateway Integration Docs](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-integration-settings-integration-request.html)
- [Lambda Proxy Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html)
- [App Runner Service URLs](https://docs.aws.amazon.com/apprunner/latest/dg/manage-configure.html)
