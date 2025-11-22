# API Gateway Troubleshooting Guide

This document provides solutions to common API Gateway integration issues and explains the modular architecture used in this template.

---

## 📚 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Migrating to Modular Setup](#migrating-to-modular-setup)
- [Testing API Gateway Integration](#testing-api-gateway-integration)
- [Debugging Tips](#debugging-tips)

---

## Architecture Overview

### Modular API Gateway Architecture

This template uses a **modular architecture** for API Gateway configuration:

```
terraform/
├── api-gateway.tf                    # Orchestrates modules
├── modules/
│   ├── api-gateway-shared/          # Shared API Gateway resources
│   │   ├── main.tf                  # REST API, stage, deployment
│   │   ├── variables.tf             # Configuration variables
│   │   └── outputs.tf               # API ID, execution ARN, etc.
│   ├── api-gateway-lambda/          # Lambda integration (AWS_PROXY)
│   │   ├── main.tf                  # Proxy resources, methods
│   │   ├── variables.tf             # Integration variables
│   │   └── outputs.tf               # Integration outputs
│   └── api-gateway-apprunner/       # App Runner integration (HTTP_PROXY)
│       ├── main.tf                  # HTTP proxy resources
│       ├── variables.tf             # Integration variables
│       └── outputs.tf               # Integration outputs
```

### Benefits of Modular Architecture

✅ **Separation of Concerns**: Shared resources separate from service-specific integrations
✅ **Reusability**: Same API Gateway can integrate multiple services
✅ **Consistency**: Standardized integration patterns
✅ **Maintainability**: Easier to update and debug
✅ **API Key Support**: Built-in authentication with usage plans

---

## Common Issues and Solutions

### Issue 1: "Lambda needs API Gateway Integration Setup"

**Symptoms:**
- API Gateway exists but has no routes
- Endpoints return 404 or "Missing Authentication Token"
- AWS Console shows "Integrations" tab is empty

**Root Cause:**
Using simplified `api-gateway.tf` without proper AWS_PROXY integration setup.

**Solution:**
Migrate to the modular API Gateway setup (see [Migrating to Modular Setup](#migrating-to-modular-setup))

---

### Issue 2: "Missing Authentication Token"

**Symptoms:**
```json
{"message": "Missing Authentication Token"}
```

**Possible Causes:**

**A. API Key Required but Not Provided**

Check if API Key is enabled:
```bash
cd terraform
terraform output api_key_id
```

If output shows an actual key ID (not "Not enabled"), you need to provide the API Key:

```bash
# Get API Key
export API_KEY=$(terraform output -raw api_key_value)

# Test with API Key
curl -H "x-api-key: $API_KEY" "$API_URL/health"
```

**B. Wrong Endpoint Path**

Ensure you're using the correct base path. If using simplified setup, paths are at root:
```bash
curl "$API_URL/health"  # ✅ Correct for simplified setup
```

If using modular setup with service prefix:
```bash
curl "$API_URL/api/health"  # ✅ Correct if service prefix enabled
```

**C. Method Not Configured**

Verify the HTTP method is configured in API Gateway:
- Check that `ANY` method exists on `/{proxy+}` resource
- Verify Lambda integration type is `AWS_PROXY`

---

### Issue 3: CORS Errors in Browser

**Symptoms:**
```
Access to fetch at '...' from origin '...' has been blocked by CORS policy
```

**Solution:**

Ensure CORS is properly configured in your `tfvars`:

```hcl
# environments/dev.tfvars
cors_allow_origins = ["*"]  # Or specific domains for production
cors_allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
cors_allow_headers = ["Content-Type", "Authorization", "X-Requested-With", "x-api-key"]
```

**Note:** If using API Key authentication, add `"x-api-key"` to `cors_allow_headers`

---

### Issue 4: API Gateway Returns 500 Internal Server Error

**Symptoms:**
```json
{"message": "Internal server error"}
```

**Debugging Steps:**

1. **Check Lambda Logs:**
```bash
# View recent logs
aws logs tail /aws/lambda/your-function-name --follow

# Or via terraform output
FUNCTION_NAME=$(cd terraform && terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$FUNCTION_NAME --follow
```

2. **Verify Lambda Execution Role:**
Ensure Lambda has permission to write CloudWatch logs

3. **Check API Gateway Logs:**
```bash
# Enable API Gateway logging in terraform
enable_api_data_trace = true  # In dev.tfvars (verbose)
api_logging_level = "INFO"
```

Then check logs:
```bash
aws logs tail /aws/apigateway/your-project-dev --follow
```

---

### Issue 5: API Key Not Working

**Symptoms:**
- API Key exists but requests still fail
- Getting "Forbidden" or "Unauthorized" errors

**Debugging Steps:**

1. **Verify API Key is Enabled:**
```bash
cd terraform
terraform output api_key_id
terraform output -raw api_key_value
```

2. **Check Usage Plan Association:**
```bash
# View usage plan
aws apigateway get-usage-plans --region us-east-1

# Verify API Key is associated
API_KEY_ID=$(cd terraform && terraform output -raw api_key_id)
aws apigateway get-usage-plan-keys --usage-plan-id <plan-id> --region us-east-1
```

3. **Verify Method Requires API Key:**
In AWS Console: API Gateway → Resources → Method Request → API Key Required should be `true`

4. **Test with Correct Header:**
```bash
# ✅ Correct header name
curl -H "x-api-key: YOUR_KEY" "$API_URL/health"

# ❌ Wrong - common mistake
curl -H "X-API-Key: YOUR_KEY" "$API_URL/health"  # Won't work
```

---

## Migrating to Modular Setup

If you have an existing project using simplified `api-gateway.tf`, follow these steps to migrate to the modular setup:

### Step 1: Copy Modules

```bash
# From your project root
cd your-project

# Copy API Gateway modules
cp -r /path/to/aws-base/terraform/modules/api-gateway-shared terraform/modules/
cp -r /path/to/aws-base/terraform/modules/api-gateway-lambda terraform/modules/

# Or if you cloned from aws-base originally
git remote add upstream https://github.com/gpazevedo/aws-base.git
git fetch upstream
git checkout upstream/main -- terraform/modules/api-gateway-shared
git checkout upstream/main -- terraform/modules/api-gateway-lambda
```

### Step 2: Backup Current Configuration

```bash
cd terraform
cp api-gateway.tf api-gateway.tf.backup
```

### Step 3: Replace with Modular Version

```bash
# Copy modular version
cp /path/to/aws-base/terraform/api-gateway.tf .
```

Or manually create with this content:

```hcl
# =============================================================================
# API Gateway Configuration (Modular)
# =============================================================================

locals {
  api_gateway_enabled = var.enable_api_gateway_standard || var.enable_api_gateway
}

module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"
  count  = local.api_gateway_enabled ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # Rate Limiting
  throttle_burst_limit = var.api_throttle_burst_limit
  throttle_rate_limit  = var.api_throttle_rate_limit

  # Logging
  log_retention_days = var.api_log_retention_days
  logging_level      = var.api_logging_level
  enable_data_trace  = var.enable_api_data_trace
  enable_xray        = var.enable_xray_tracing

  # Caching
  enable_caching = var.enable_api_caching

  # CORS
  cors_allow_origins = var.cors_allow_origins
  cors_allow_methods = var.cors_allow_methods
  cors_allow_headers = var.cors_allow_headers

  # API Key
  enable_api_key          = var.enable_api_key
  api_key_name            = var.api_key_name
  usage_plan_quota_limit  = var.api_usage_plan_quota_limit
  usage_plan_quota_period = var.api_usage_plan_quota_period
}

module "api_gateway_lambda" {
  source = "./modules/api-gateway-lambda"
  count  = local.api_gateway_enabled ? 1 : 0

  api_id               = module.api_gateway_shared[0].api_id
  api_root_resource_id = module.api_gateway_shared[0].root_resource_id
  api_execution_arn    = module.api_gateway_shared[0].execution_arn

  lambda_function_name = aws_lambda_function.api.function_name
  lambda_function_arn  = aws_lambda_function.api.arn
  lambda_invoke_arn    = aws_lambda_function.api.invoke_arn

  enable_root_method   = true
  api_key_required     = var.enable_api_key
}
```

### Step 4: Initialize and Apply

```bash
# Reinitialize to recognize new modules
terraform init -var-file="environments/dev.tfvars"

# Plan changes
terraform plan -var-file="environments/dev.tfvars"

# Apply
terraform apply -var-file="environments/dev.tfvars"
```

### Step 5: Update API Key Settings (if needed)

```bash
# Edit your environment tfvars
vim environments/dev.tfvars
```

Ensure API Key is enabled:
```hcl
enable_api_key = true
```

### Step 6: Test Integration

```bash
# Get outputs
export API_URL=$(terraform output -raw primary_endpoint)
export API_KEY=$(terraform output -raw api_key_value)

# Test with API Key
curl -H "x-api-key: $API_KEY" "$API_URL/health" | jq

# Verify response
# Expected: {"status":"healthy","timestamp":"...","uptime_seconds":...,"version":"0.1.0"}
```

---

## Testing API Gateway Integration

### Test Checklist

- [ ] **Basic Connectivity**
  ```bash
  curl "$API_URL/health"
  ```

- [ ] **API Key Authentication** (if enabled)
  ```bash
  curl -H "x-api-key: $API_KEY" "$API_URL/health"
  ```

- [ ] **Different HTTP Methods**
  ```bash
  # GET
  curl -H "x-api-key: $API_KEY" "$API_URL/greet?name=Alice"

  # POST
  curl -X POST -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
    "$API_URL/greet" -d '{"name":"Bob"}'
  ```

- [ ] **CORS Preflight**
  ```bash
  curl -X OPTIONS -H "Origin: http://localhost:3000" \
    -H "Access-Control-Request-Method: POST" \
    -H "Access-Control-Request-Headers: x-api-key" \
    "$API_URL/health" -v
  ```

- [ ] **Interactive Documentation**
  ```bash
  # Open in browser
  open "$API_URL/docs"

  # Or curl to verify
  curl "$API_URL/docs" -H "x-api-key: $API_KEY"
  ```

- [ ] **Error Handling**
  ```bash
  # Test 404
  curl -H "x-api-key: $API_KEY" "$API_URL/nonexistent"

  # Test 500
  curl -H "x-api-key: $API_KEY" "$API_URL/error"
  ```

---

## Debugging Tips

### Enable Detailed Logging

In `environments/dev.tfvars`:

```hcl
# Verbose API Gateway logging
api_logging_level = "INFO"
enable_api_data_trace = true  # Log full request/response (dev only!)
enable_xray_tracing = true    # Enable X-Ray tracing

# Longer log retention for debugging
api_log_retention_days = 7
```

### View CloudWatch Logs

```bash
# Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# API Gateway logs
aws logs tail /aws/apigateway/$(terraform output -raw project_name)-dev --follow
```

### Test Lambda Function Directly

```bash
# Invoke Lambda directly (bypass API Gateway)
aws lambda invoke \
  --function-name $(cd terraform && terraform output -raw lambda_function_name) \
  --payload '{"httpMethod":"GET","path":"/health"}' \
  response.json

cat response.json | jq
```

### Check API Gateway Configuration

```bash
# Get API ID
API_ID=$(cd terraform && terraform output -raw api_gateway_id)

# List resources
aws apigateway get-resources --rest-api-id $API_ID

# Get specific method
aws apigateway get-method --rest-api-id $API_ID \
  --resource-id <resource-id> --http-method ANY
```

### Verify Lambda Permissions

```bash
# Check if API Gateway can invoke Lambda
aws lambda get-policy \
  --function-name $(cd terraform && terraform output -raw lambda_function_name)
```

Should include a statement allowing `apigateway.amazonaws.com` to invoke the function.

---

## Quick Reference

### Common Error Messages

| Error | Likely Cause | Solution |
|-------|--------------|----------|
| `Missing Authentication Token` | Wrong path, missing API Key, or no integration | Check path, provide API Key, verify integration exists |
| `Forbidden` | API Key invalid or missing | Verify API Key value and header name (`x-api-key`) |
| `Internal server error` | Lambda error or misconfiguration | Check Lambda logs, verify handler exists |
| `{"message":"Endpoint request timed out"}` | Lambda timeout | Increase Lambda timeout or optimize code |
| CORS error | Missing CORS headers | Add origin to `cors_allow_origins`, enable OPTIONS method |

### Useful Commands

```bash
# Get all outputs
cd terraform && terraform output

# Get specific output
terraform output -raw primary_endpoint
terraform output -raw api_key_value

# View recent Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# Test endpoint with API Key
curl -H "x-api-key: $(terraform output -raw api_key_value)" \
  "$(terraform output -raw primary_endpoint)/health" | jq
```

---

## Additional Resources

- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [Lambda Proxy Integration](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html)
- [API Gateway API Keys](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-setup-api-key-with-console.html)
- [CORS Configuration](https://docs.aws.amazon.com/apigateway/latest/developerguide/how-to-cors.html)
