# Multi-Service API Gateway Testing Guide

## Overview

This guide provides comprehensive testing scenarios for the multi-service API Gateway architecture with path-based routing.

## Prerequisites

- Terraform backend already configured (`make setup-terraform-backend`)
- AWS credentials configured
- Docker installed and logged into ECR
- Project directory structure in place

## Test Scenario 1: Single Lambda Service (Root Path)

### Objective
Verify that creating the first Lambda service creates `api-gateway.tf` with shared module and root path integration.

### Steps

```bash
# 1. Create 'api' Lambda service (should create api-gateway.tf)
./scripts/setup-terraform-lambda.sh api false

# 2. Verify file structure
ls -la terraform/
# Expected: lambda-api.tf exists
# Expected: api-gateway.tf exists (newly created)

# 3. Check api-gateway.tf content
grep -A 5 "module \"api_gateway_shared\"" terraform/api-gateway.tf
grep -A 10 "module \"api_gateway_lambda_api\"" terraform/api-gateway.tf

# 4. Verify path_prefix is empty (root path)
grep "path_prefix.*=.*\"\"" terraform/api-gateway.tf

# 5. Build and push Docker image
./scripts/docker-push.sh dev api Dockerfile.lambda

# 6. Deploy
cd terraform
terraform init -upgrade
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars -auto-approve

# 7. Test endpoints
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl $PRIMARY_URL/health         # Should return 200 from 'api' service
curl "$PRIMARY_URL/greet?name=Test"  # Should return greeting
curl $PRIMARY_URL/docs           # Should return OpenAPI docs

# 8. Verify routing
echo "Expected: All requests to / and /* route to 'api' service"
```

### Expected Results

- ✅ `terraform/api-gateway.tf` created with modular structure
- ✅ Contains `module "api_gateway_shared"` (shared gateway)
- ✅ Contains `module "api_gateway_lambda_api"` with `path_prefix = ""`
- ✅ `enable_root_method = true` for 'api' service
- ✅ All root path requests (/, /health, /greet, /docs) route to 'api' service
- ✅ Terraform apply succeeds with no errors

---

## Test Scenario 2: Add Second Lambda Service (Path-Based)

### Objective
Verify that adding a second Lambda service appends integration without overwriting `api-gateway.tf`.

### Steps

```bash
# 1. Create 'worker' Lambda service (should append to api-gateway.tf)
./scripts/setup-terraform-lambda.sh worker false

# 2. Verify file structure
ls -la terraform/
# Expected: lambda-worker.tf exists (new)
# Expected: api-gateway.tf exists (NOT overwritten)

# 3. Check api-gateway.tf was appended
grep -A 10 "module \"api_gateway_lambda_worker\"" terraform/api-gateway.tf

# 4. Verify path_prefix is "worker"
grep "path_prefix.*=.*\"worker\"" terraform/api-gateway.tf

# 5. Verify both integrations exist
grep "module \"api_gateway_lambda_api\"" terraform/api-gateway.tf
grep "module \"api_gateway_lambda_worker\"" terraform/api-gateway.tf

# 6. Build and push Docker image for worker
./scripts/docker-push.sh dev worker Dockerfile.lambda

# 7. Deploy
cd terraform
terraform init -upgrade
terraform plan -var-file=environments/dev.tfvars
# Should show: Adding worker integration, no changes to 'api' integration
terraform apply -var-file=environments/dev.tfvars -auto-approve

# 8. Test both services
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl $PRIMARY_URL/health          # 'api' service
curl $PRIMARY_URL/worker/health   # 'worker' service
curl $PRIMARY_URL/worker/jobs     # 'worker' service (if endpoint exists)

# 9. Verify routing
echo "Expected: /worker/* routes to 'worker' service"
echo "Expected: /* still routes to 'api' service"
```

### Expected Results

- ✅ `terraform/api-gateway.tf` NOT overwritten, integration appended
- ✅ Contains both `api_gateway_lambda_api` and `api_gateway_lambda_worker`
- ✅ 'worker' service has `path_prefix = "worker"`
- ✅ 'worker' service has `enable_root_method = false`
- ✅ `/worker` and `/worker/*` route to 'worker' service
- ✅ Root paths still route to 'api' service
- ✅ Terraform apply adds only new resources, no changes to existing

---

## Test Scenario 3: Add Third Lambda Service

### Objective
Verify scalability by adding a third service.

### Steps

```bash
# 1. Create 'scheduler' Lambda service
./scripts/setup-terraform-lambda.sh scheduler false

# 2. Verify api-gateway.tf has three integrations
grep "module \"api_gateway_lambda_" terraform/api-gateway.tf
# Expected: api, worker, scheduler

# 3. Build and deploy
./scripts/docker-push.sh dev scheduler Dockerfile.lambda
cd terraform
terraform apply -var-file=environments/dev.tfvars -auto-approve

# 4. Test all three services
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl $PRIMARY_URL/health              # 'api'
curl $PRIMARY_URL/worker/health       # 'worker'
curl $PRIMARY_URL/scheduler/health    # 'scheduler'
```

### Expected Results

- ✅ Three integrations in `api-gateway.tf`
- ✅ Each service accessible at its designated path
- ✅ No conflicts or overwrites

---

## Test Scenario 4: Idempotency Check

### Objective
Verify that re-running the same service setup is safe (doesn't duplicate).

### Steps

```bash
# 1. Re-run setup for existing service
./scripts/setup-terraform-lambda.sh worker false

# Expected output: "ℹ️  Integration for 'worker' already exists in api-gateway.tf"

# 2. Check api-gateway.tf
grep -c "module \"api_gateway_lambda_worker\"" terraform/api-gateway.tf
# Expected: 1 (not duplicated)

# 3. Run terraform plan
cd terraform
terraform plan -var-file=environments/dev.tfvars
# Expected: No changes
```

### Expected Results

- ✅ Script detects existing integration
- ✅ Skips append with info message
- ✅ No duplicate modules created
- ✅ Terraform plan shows no changes

---

## Test Scenario 5: AppRunner Service with API Gateway Integration

### Objective
Verify AppRunner services can be added to existing API Gateway.

### Steps

```bash
# 1. Create AppRunner service (with existing api-gateway.tf)
./scripts/setup-terraform-apprunner.sh web

# When prompted: "Add AppRunner integration to API Gateway? (y/N):"
# Press 'y' to integrate

# 2. Verify api-gateway.tf has AppRunner integration
grep "module \"api_gateway_apprunner_web\"" terraform/api-gateway.tf

# 3. Verify path_prefix is "web"
grep -A 15 "module \"api_gateway_apprunner_web\"" terraform/api-gateway.tf | grep "path_prefix"

# 4. Build and deploy
./scripts/docker-push.sh dev web Dockerfile.apprunner
cd terraform
terraform apply -var-file=environments/dev.tfvars -auto-approve

# 5. Test mixed Lambda + AppRunner
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl $PRIMARY_URL/health       # Lambda 'api'
curl $PRIMARY_URL/worker/health # Lambda 'worker'
curl $PRIMARY_URL/web/health   # AppRunner 'web'

# 6. Test direct AppRunner URL
APPRUNNER_WEB_URL=$(terraform output -raw apprunner_web_url)
curl $APPRUNNER_WEB_URL/health
```

### Expected Results

- ✅ Script prompts for API Gateway integration
- ✅ Appends AppRunner integration to existing `api-gateway.tf`
- ✅ AppRunner service accessible via `/web` path on API Gateway
- ✅ AppRunner service also accessible via direct URL
- ✅ Both Lambda and AppRunner services work together

---

## Test Scenario 6: AppRunner Without API Gateway

### Objective
Verify AppRunner services work independently when API Gateway doesn't exist.

### Steps

```bash
# 1. Start fresh OR skip API Gateway integration prompt
./scripts/setup-terraform-apprunner.sh standalone

# When prompted: "Add AppRunner integration to API Gateway? (y/N):"
# Press 'N' to skip (or api-gateway.tf doesn't exist)

# Expected output: "⏭️  Skipped AppRunner API Gateway integration"
# OR: "ℹ️  No API Gateway configuration found"

# 2. Verify no API Gateway integration added
grep "api_gateway_apprunner_standalone" terraform/api-gateway.tf
# Expected: Not found (or file doesn't exist)

# 3. Deploy
cd terraform
terraform apply -var-file=environments/dev.tfvars -auto-approve

# 4. Test via direct AppRunner URL only
APPRUNNER_URL=$(terraform output -raw apprunner_standalone_url)
curl $APPRUNNER_URL/health
```

### Expected Results

- ✅ AppRunner service deployed successfully
- ✅ No API Gateway integration created
- ✅ Service accessible via direct AppRunner URL
- ✅ Terraform apply succeeds

---

## Test Scenario 7: Migration from Single Service to Multi-Service

### Objective
Verify existing single-service deployments can migrate to multi-service architecture.

### Prerequisites
- Existing deployment with old `api-gateway.tf` structure

### Steps

```bash
# 1. Backup existing api-gateway.tf
cp terraform/api-gateway.tf terraform/api-gateway.tf.backup

# 2. Check current state
cd terraform
terraform state list | grep api_gateway

# 3. Remove old api-gateway.tf
rm terraform/api-gateway.tf

# 4. Regenerate with new structure
cd ..
./scripts/setup-terraform-lambda.sh api false

# 5. Initialize and check plan
cd terraform
terraform init -upgrade
terraform plan -var-file=environments/dev.tfvars

# Expected: Terraform wants to recreate API Gateway resources
# This is expected due to module path changes

# 6. Review changes carefully
# - API Gateway will be recreated (new resource names due to module)
# - Lambda functions remain unchanged
# - May cause brief downtime

# 7. Apply if acceptable
terraform apply -var-file=environments/dev.tfvars

# 8. Verify endpoints still work
PRIMARY_URL=$(terraform output -raw primary_endpoint)
curl $PRIMARY_URL/health
```

### Expected Results

- ✅ New modular structure created
- ⚠️  API Gateway resources recreated (brief downtime)
- ✅ Lambda functions unchanged
- ✅ All endpoints functional after migration
- ✅ Can now add additional services

### Migration Notes

- **Downtime:** Expect brief API Gateway downtime during resource recreation
- **Custom Domain:** If using custom domain, DNS may need to propagate
- **Recommendation:** Perform during maintenance window

---

## Troubleshooting

### Issue: "Integration already exists" but not in file

**Cause:** Grep pattern matched a comment or other text

**Solution:**
```bash
# Check exact pattern
grep -n "module \"api_gateway_lambda_SERVICE_NAME\"" terraform/api-gateway.tf

# If false positive, manually verify and re-run
```

### Issue: Terraform plan shows unexpected changes

**Cause:** Module path changed or variables modified

**Solution:**
```bash
# Reinitialize modules
terraform init -upgrade

# Check for syntax errors
terraform validate

# Review specific resource changes
terraform plan -var-file=environments/dev.tfvars | grep -A 10 "api_gateway"
```

### Issue: Path-based routing not working

**Cause:** API Gateway deployment didn't update

**Solution:**
```bash
# Force API Gateway redeployment
cd terraform
terraform taint 'module.api_gateway_shared[0].aws_api_gateway_deployment.api'
terraform apply -var-file=environments/dev.tfvars -auto-approve
```

### Issue: 403 Forbidden from API Gateway

**Cause:** API Key required but not provided

**Solution:**
```bash
# Check if API Key is enabled
grep "enable_api_key" terraform/environments/dev.tfvars

# Get API Key value
cd terraform
terraform output api_key_value

# Test with API Key
curl -H "x-api-key: YOUR_KEY_HERE" $PRIMARY_URL/health
```

### Issue: AppRunner integration prompt not showing

**Cause:** `api-gateway.tf` doesn't exist

**Solution:**
```bash
# Create at least one Lambda service first
./scripts/setup-terraform-lambda.sh api false

# Then create AppRunner service
./scripts/setup-terraform-apprunner.sh web
```

---

## Verification Checklist

After deploying multiple services, verify:

- [ ] All service-specific `.tf` files exist (`lambda-*.tf`, `apprunner-*.tf`)
- [ ] Single `api-gateway.tf` contains all integrations
- [ ] Shared module (`api_gateway_shared`) created only once
- [ ] Each Lambda integration has correct `path_prefix`
- [ ] 'api' service has `path_prefix = ""` and `enable_root_method = true`
- [ ] Other services have `path_prefix = "SERVICE_NAME"` and `enable_root_method = false`
- [ ] `terraform plan` shows no unexpected changes
- [ ] All service endpoints return 200 OK
- [ ] Path-based routing works correctly
- [ ] API Gateway CloudWatch logs show requests routing to correct Lambdas

---

## Performance Testing

Test API Gateway with multiple services under load:

```bash
# Install Apache Bench (if not installed)
# Ubuntu/Debian: apt-get install apache2-utils
# macOS: brew install ab

PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

# Test 'api' service (root path)
ab -n 1000 -c 10 $PRIMARY_URL/health

# Test 'worker' service (path-based)
ab -n 1000 -c 10 $PRIMARY_URL/worker/health

# Monitor CloudWatch Logs
# Check that requests are distributed correctly
```

---

## Cleanup

To remove test deployments:

```bash
cd terraform
terraform destroy -var-file=environments/dev.tfvars -auto-approve

# Remove generated files (optional)
rm -f lambda-*.tf apprunner-*.tf api-gateway.tf
```

---

## Next Steps

After successful testing:

1. ✅ Deploy to staging environment
2. ✅ Run integration tests across all services
3. ✅ Monitor CloudWatch logs for routing correctness
4. ✅ Set up alarms for API Gateway 4xx/5xx errors
5. ✅ Document service-specific endpoints for team
6. ✅ Deploy to production with appropriate API Key configuration
