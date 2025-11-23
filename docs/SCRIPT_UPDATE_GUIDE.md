# Setup Script Update Guide

## Overview
This document describes the changes needed to `setup-terraform-lambda.sh` and `setup-terraform-apprunner.sh` to support automatic API Gateway integration appending.

## Changes to setup-terraform-lambda.sh

### Location
Replace lines **476-622** (the old api-gateway.tf creation section)

### Old Behavior
- Always creates `api-gateway.tf` with hardcoded single-service configuration
- Overwrites existing file

### New Behavior
- Creates `api-gateway.tf` with modular structure if it doesn't exist
- Appends new service integration if file exists
- Skips if service integration already present

### Replacement Code

Replace the section starting with:
```bash
# =============================================================================
# Create api-gateway.tf (optional)
# =============================================================================
```

With:
```bash
# =============================================================================
# Smart API Gateway Integration Management
# =============================================================================
# Either creates api-gateway.tf or appends new service integration

API_GATEWAY_FILE="$TERRAFORM_DIR/api-gateway.tf"

# Determine path_prefix based on service name
if [ "$SERVICE_NAME" = "api" ]; then
  PATH_PREFIX=""  # Root path for 'api' service
  ENABLE_ROOT="true"
else
  PATH_PREFIX="$SERVICE_NAME"  # Path-based for other services
  ENABLE_ROOT="false"
fi

# Check if API Gateway file exists
if [ ! -f "$API_GATEWAY_FILE" ]; then
  echo "📝 Creating terraform/api-gateway.tf (new modular structure)..."

  cat > "$API_GATEWAY_FILE" <<'EOF'
# =============================================================================
# API Gateway Configuration (Standard Mode)
# =============================================================================
# This file configures API Gateway as the standard entry point for services
# Uses modular architecture for shared configuration and service-specific integrations
# =============================================================================

locals {
  # Determine if API Gateway should be enabled
  api_gateway_enabled = var.enable_api_gateway_standard || var.enable_api_gateway
}

# =============================================================================
# Shared API Gateway Module
# =============================================================================

module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"
  count  = local.api_gateway_enabled ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  api_name     = "${var.project_name}-${var.environment}-api"

  # Rate Limiting
  throttle_burst_limit = var.api_throttle_burst_limit
  throttle_rate_limit  = var.api_throttle_rate_limit

  # Logging and Monitoring
  log_retention_days   = var.api_log_retention_days
  api_logging_level    = var.api_logging_level
  enable_data_trace    = var.enable_api_data_trace
  enable_xray_tracing  = var.enable_xray_tracing

  # Caching
  enable_caching = var.enable_api_caching

  # API Key Authentication
  enable_api_key          = var.enable_api_key
  api_key_name            = var.api_key_name
  usage_plan_quota_limit  = var.api_usage_plan_quota_limit
  usage_plan_quota_period = var.api_usage_plan_quota_period

  tags = var.additional_tags
}

# =============================================================================
# Lambda Service Integrations
# =============================================================================

EOF

  echo "✅ Created new api-gateway.tf with shared module"
fi

# Check if this service integration already exists
if grep -q "module \"api_gateway_lambda_${SERVICE_NAME}\"" "$API_GATEWAY_FILE"; then
  echo "ℹ️  Integration for '${SERVICE_NAME}' already exists in api-gateway.tf"
else
  echo "📝 Appending integration for '${SERVICE_NAME}' to api-gateway.tf..."

  cat >> "$API_GATEWAY_FILE" <<EOF

# Integration for '${SERVICE_NAME}' Lambda service
module "api_gateway_lambda_${SERVICE_NAME}" {
  source = "./modules/api-gateway-lambda-integration"
  count  = local.api_gateway_enabled ? 1 : 0

  service_name = "${SERVICE_NAME}"
  path_prefix  = "${PATH_PREFIX}"  # $([ -z "$PATH_PREFIX" ] && echo "Empty = root (/, /*)" || echo "/${PATH_PREFIX}, /${PATH_PREFIX}/*")

  api_id                = module.api_gateway_shared[0].api_id
  api_root_resource_id  = module.api_gateway_shared[0].root_resource_id
  api_execution_arn     = module.api_gateway_shared[0].execution_arn

  lambda_function_name  = aws_lambda_function.${SERVICE_NAME}.function_name
  lambda_invoke_arn     = aws_lambda_function.${SERVICE_NAME}.invoke_arn

  enable_root_method    = ${ENABLE_ROOT}
  api_key_required      = var.enable_api_key
}
EOF

  echo "✅ Added integration for '${SERVICE_NAME}'"
fi

echo ""
```

## Changes to setup-terraform-apprunner.sh

### Current State
The script already skips `api-gateway.tf` creation (disabled at line 550-654)

### Action Needed
Add similar append logic for AppRunner integrations (optional, for future multi-service AppRunner+Lambda setups)

### Location
After the `apprunner-{service}.tf` creation, around line 550

### Optional Append Code

```bash
# =============================================================================
# Optionally Append AppRunner Integration to API Gateway
# =============================================================================
# This allows AppRunner services to be accessed through API Gateway

API_GATEWAY_FILE="$TERRAFORM_DIR/api-gateway.tf"

if [ -f "$API_GATEWAY_FILE" ]; then
  # API Gateway exists, offer to add AppRunner integration
  echo ""
  echo "📌 API Gateway configuration detected"
  read -p "Add AppRunner integration to API Gateway? (y/N): " -n 1 -r
  echo

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    PATH_PREFIX="${SERVICE_NAME}"  # AppRunner always uses path-based

    if ! grep -q "module \"api_gateway_apprunner_${SERVICE_NAME}\"" "$API_GATEWAY_FILE"; then
      echo "📝 Appending AppRunner integration for '${SERVICE_NAME}'..."

      cat >> "$API_GATEWAY_FILE" <<EOF

# Integration for '${SERVICE_NAME}' AppRunner service
module "api_gateway_apprunner_${SERVICE_NAME}" {
  source = "./modules/api-gateway-apprunner-integration"
  count  = local.api_gateway_enabled ? 1 : 0

  service_name          = "${SERVICE_NAME}"
  path_prefix           = "${PATH_PREFIX}"  # /${PATH_PREFIX}, /${PATH_PREFIX}/*

  api_id                = module.api_gateway_shared[0].api_id
  api_root_resource_id  = module.api_gateway_shared[0].root_resource_id
  api_execution_arn     = module.api_gateway_shared[0].execution_arn

  apprunner_service_url = aws_apprunner_service.${SERVICE_NAME}.service_url

  enable_root_method    = false
  api_key_required      = var.enable_api_key
}
EOF

      echo "✅ Added AppRunner integration for '${SERVICE_NAME}'"
    else
      echo "ℹ️  Integration already exists"
    fi
  else
    echo "⏭️  Skipped AppRunner API Gateway integration"
  fi
fi
```

## Testing the Changes

### Test 1: Create First Lambda Service
```bash
./scripts/setup-terraform-lambda.sh api

# Expected:
# - Creates terraform/api-gateway.tf with shared module
# - Appends api_gateway_lambda_api integration (root path)
```

### Test 2: Create Second Lambda Service
```bash
./scripts/setup-terraform-lambda.sh worker

# Expected:
# - Does NOT overwrite api-gateway.tf
# - Appends api_gateway_lambda_worker integration (path: /worker/*)
```

### Test 3: Re-run Same Service
```bash
./scripts/setup-terraform-lambda.sh worker

# Expected:
# - Detects existing integration
# - Skips append, shows info message
```

### Test 4: Create AppRunner Service (Optional)
```bash
./scripts/setup-terraform-apprunner.sh web

# Expected (if integration prompt accepted):
# - Appends api_gateway_apprunner_web integration
```

## Migration for Existing Users

If you have an existing `terraform/api-gateway.tf` from the old structure:

1. **Backup existing file:**
   ```bash
   cp terraform/api-gateway.tf terraform/api-gateway.tf.backup
   ```

2. **Remove old file and regenerate:**
   ```bash
   rm terraform/api-gateway.tf
   ./scripts/setup-terraform-lambda.sh api
   ```

3. **Verify with terraform:**
   ```bash
   cd terraform
   terraform init -upgrade
   terraform plan
   ```

## Benefits

✅ **No Overwrites** - Each service is appended, not replaced
✅ **Idempotent** - Running script multiple times is safe
✅ **Path-Based Routing** - Automatic for non-'api' services
✅ **Single API Gateway** - All services share one gateway
✅ **Modular Structure** - Clean, maintainable code

## Implementation Status

- [x] Design append logic
- [x] Test append logic separately
- [x] Document changes needed
- [ ] Apply changes to setup-terraform-lambda.sh
- [ ] Apply changes to setup-terraform-apprunner.sh
- [ ] Test with multiple services
- [ ] Update README.md

## Manual Application

To apply these changes manually:

1. Open `scripts/setup-terraform-lambda.sh`
2. Find line 476 (`# Create api-gateway.tf (optional)`)
3. Delete through line 622 (end of api-gateway.tf creation)
4. Insert the new "Smart API Gateway Integration Management" code
5. Save and test

**Note:** The full implementation requires careful editing due to the size of the script. Consider using a text editor with line numbers for precision.
