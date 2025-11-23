# API Gateway Multi-Service Refactoring Plan

## Overview
Refactor API Gateway configuration to support multiple backend services (Lambda and AppRunner) without file conflicts.

## Current Problems

1. **API Gateway Created Per Service** ❌
   - `setup-terraform-lambda.sh` creates `api-gateway.tf`
   - `setup-terraform-apprunner.sh` creates `api-gateway.tf`
   - Each service would **overwrite** the previous one
   - No support for multiple services behind one API Gateway

2. **Hardcoded Service Reference** ❌
   - `api-gateway.tf:63-64` hardcodes `aws_lambda_function.api`
   - Won't work when you add `worker`, `scheduler`, etc.

## Proposed Architecture

```
terraform/
├── api-gateway.tf              # Shared API Gateway (ONE per environment)
│   ├── module "api_gateway_shared"           # REST API, stage, logging
│   ├── module "api_gateway_lambda_api"       # Integration for 'api' service
│   ├── module "api_gateway_lambda_worker"    # Integration for 'worker' service
│   └── module "api_gateway_apprunner_web"    # Integration for 'web' service
│
├── lambda-api.tf               # API service Lambda
│   └── aws_lambda_function.api
│
├── lambda-worker.tf            # Worker service Lambda
│   └── aws_lambda_function.worker
│
└── apprunner-web.tf            # Web App Runner service
    └── aws_apprunner_service.web
```

## Implementation Phases

### Phase 1: Rename Module for Clarity
- Rename `api-gateway-lambda` → `api-gateway-lambda-integration`
- Makes it clear this module integrates **one service** with API Gateway
- Each service gets its own integration module instance

### Phase 2: Update api-gateway.tf Structure

**Before (hardcoded for one service):**
```hcl
module "api_gateway_lambda" {
  source = "./modules/api-gateway-lambda"
  lambda_function_name = aws_lambda_function.api.function_name
  lambda_invoke_arn    = aws_lambda_function.api.invoke_arn
}
```

**After (supports multiple services):**
```hcl
# Shared API Gateway infrastructure
module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"
  count  = local.api_gateway_enabled ? 1 : 0
  # ... config
}

# Integration for 'api' service
module "api_gateway_lambda_api" {
  source = "./modules/api-gateway-lambda-integration"
  count  = local.api_gateway_enabled ? 1 : 0

  service_name         = "api"
  api_id               = module.api_gateway_shared[0].api_id
  api_root_resource_id = module.api_gateway_shared[0].root_resource_id
  api_execution_arn    = module.api_gateway_shared[0].execution_arn

  lambda_function_name = aws_lambda_function.api.function_name
  lambda_invoke_arn    = aws_lambda_function.api.invoke_arn

  enable_root_method   = true
  api_key_required     = var.enable_api_key
}

# Future services added by script:
# module "api_gateway_lambda_worker" { ... }
# module "api_gateway_apprunner_web" { ... }
```

### Phase 3: Update setup-terraform-lambda.sh

The script should:
1. ✅ Generate `lambda-<service>.tf` (already does this)
2. **NEW**: Check if `api-gateway.tf` exists
   - If NO: Create it with shared module + first integration
   - If YES: **Append** new service integration module block
3. **NEW**: Add service name parameter to integration module
4. **NEW**: Support path-based routing (e.g., `/api/*`, `/worker/*`)

### Phase 4: Update setup-terraform-apprunner.sh

The script should:
1. Generate `apprunner-<service>.tf` (similar to lambda pattern)
2. **Don't overwrite** `api-gateway.tf` if it already exists
3. **Append** AppRunner integration to existing `api-gateway.tf`
4. Create `api-gateway-apprunner-integration` module if needed

## Benefits

✅ **Single API Gateway** - One REST API for all services
✅ **Service Isolation** - Each service in its own file
✅ **Scalable** - Easy to add new services without conflicts
✅ **Modular** - Reusable integration modules
✅ **Path-based Routing** - `/api/*`, `/worker/*`, `/web/*`
✅ **Script Safety** - Scripts won't overwrite each other's files

## Files to Modify

1. `terraform/modules/api-gateway-lambda/` → Rename to `api-gateway-lambda-integration/`
2. `terraform/api-gateway.tf` - Update to support multiple service integrations
3. `scripts/setup-terraform-lambda.sh` - Support appending integrations
4. `scripts/setup-terraform-apprunner.sh` - Support multi-service pattern
5. `docs/` - Update documentation

## Testing Plan

1. Test creating first Lambda service (should create api-gateway.tf)
2. Test creating second Lambda service (should append to api-gateway.tf)
3. Test creating AppRunner service (should append to existing api-gateway.tf)
4. Test terraform plan/apply with multiple services
5. Verify API Gateway routes correctly to each service

## Status

- [x] Architecture design complete
- [x] Multi-Lambda services implemented
- [x] Multi-AppRunner services implemented
- [x] **Decided on routing strategy:** Path-based routing with 'api' service at root
- [x] Module rename (`api-gateway-lambda` → `api-gateway-lambda-integration`)
- [x] Module rename (`api-gateway-apprunner` → `api-gateway-apprunner-integration`)
- [x] Update api-gateway.tf structure (modular with shared + per-service integrations)
- [x] Update setup-terraform-lambda.sh to append integrations (smart append logic)
- [x] Update setup-terraform-apprunner.sh to append integrations (optional prompt)
- [x] Documentation updates (README.md, SCRIPT_UPDATE_GUIDE.md, IMPLEMENTATION_STATUS.md)
- [ ] Testing with multiple services (deployment validation)
- [ ] Create comprehensive testing guide

## Important Design Decisions Needed

### 1. Routing Strategy

**Option A: Path-Based Routing** (Recommended for multi-service)

- Each service gets its own path prefix: `/api/*`, `/worker/*`, `/web/*`
- Requires updating module to support `path_prefix` parameter
- Clean separation, explicit routing

**Option B: Single Service Root Access** (Current, limited)

- One service handles `/*` and `/`, others get specific paths
- Works for simple cases (1 Lambda + optional AppRunner services)
- Not scalable for many services

### 2. Backward Compatibility

For existing deployments using the current single-service pattern:

- Provide migration guide
- Support both patterns via configuration flag?
- Default to single-service for compatibility, opt-in to multi-service?

## Notes

- `lambda.tf` was removed and will be generated by scripts as `lambda-<service>.tf`
- Multi-AppRunner services now follow the same pattern as multi-Lambda services
- Current `api-gateway.tf` hardcodes references to `aws_lambda_function.api`
- Path-based routing requires changes to the integration module variables
