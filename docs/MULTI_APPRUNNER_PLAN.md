# Multi-AppRunner Services Implementation Plan

## Overview
Enable multiple AppRunner services following the same pattern as multi-Lambda services.

## Current State

### Lambda Pattern (✅ Already Implemented)
```bash
# Create services
./scripts/setup-terraform-lambda.sh api
./scripts/setup-terraform-lambda.sh worker
./scripts/setup-terraform-lambda.sh scheduler

# Generated files
terraform/lambda-api.tf
terraform/lambda-worker.tf
terraform/lambda-scheduler.tf

# Testing
make test-lambda-api
make test-lambda-worker
./scripts/test-lambda.sh scheduler
```

### AppRunner Pattern (❌ Not Yet Implemented)
```bash
# Current (single service only)
./scripts/setup-terraform-apprunner.sh

# Generates
terraform/apprunner.tf  # Hardcoded, no service name

# Desired (multi-service)
./scripts/setup-terraform-apprunner.sh web
./scripts/setup-terraform-apprunner.sh admin
./scripts/setup-terraform-apprunner.sh dashboard

# Should generate
terraform/apprunner-web.tf
terraform/apprunner-admin.tf
terraform/apprunner-dashboard.tf
```

## Implementation Plan

### Phase 1: Update setup-terraform-apprunner.sh

**Key Changes:**

1. **Add SERVICE_NAME parameter** (like Lambda script)
   ```bash
   # Parse command line arguments
   SERVICE_NAME="${1:-apprunner}"  # Default: 'apprunner' for backward compatibility
   ENABLE_API_KEY="${2:-true}"     # Default: enabled
   ```

2. **Validate service directory**
   ```bash
   if [ ! -d "backend/${SERVICE_NAME}" ]; then
     echo "❌ Error: Service directory not found: backend/${SERVICE_NAME}"
     exit 1
   fi
   ```

3. **Generate service-specific file**: `apprunner-<service>.tf`
   ```bash
   APPRUNNER_TF_FILE="$TERRAFORM_DIR/apprunner-${SERVICE_NAME}.tf"
   ```

4. **Use template with placeholders**
   ```hcl
   resource "aws_apprunner_service" "SERVICE_NAME_PLACEHOLDER" {
     service_name = "${var.project_name}-${var.environment}-SERVICE_NAME_PLACEHOLDER"
     # ...
   }
   ```

5. **Generate service-specific outputs**
   ```hcl
   output "apprunner_SERVICE_NAME_PLACEHOLDER_url" {
     description = "App Runner service URL for SERVICE_NAME_PLACEHOLDER"
     value       = aws_apprunner_service.SERVICE_NAME_PLACEHOLDER.service_url
   }
   ```

6. **Don't overwrite shared files**
   - `main.tf` - Only create if doesn't exist
   - `variables.tf` - Only create if doesn't exist
   - `api-gateway.tf` - Skip creation (will be handled by API Gateway refactoring)
   - `environments/*.tfvars` - Only create if doesn't exist

### Phase 2: Create test-apprunner.sh Script

Follow the pattern from `test-lambda.sh`:

```bash
#!/bin/bash
# Usage: ./scripts/test-apprunner.sh SERVICE_NAME [ENVIRONMENT]
# Examples:
#   ./scripts/test-apprunner.sh web
#   ./scripts/test-apprunner.sh admin dev

SERVICE_NAME="${1:-apprunner}"
ENVIRONMENT="${2:-dev}"

# Get service URL from Terraform outputs
SERVICE_URL=$(cd terraform && terraform output -raw apprunner_${SERVICE_NAME}_url 2>/dev/null || echo "")

if [ -z "$SERVICE_URL" ]; then
  echo "❌ Error: Service '${SERVICE_NAME}' not found"
  echo "Available AppRunner services:"
  cd terraform && terraform output -json 2>/dev/null | \
    jq -r 'keys[] | select(startswith("apprunner_") and endswith("_url"))' | \
    sed 's/apprunner_//g' | sed 's/_url//g'
  exit 1
fi

# Test endpoints
curl "${SERVICE_URL}/health"
curl "${SERVICE_URL}/docs"
```

### Phase 3: Update Makefile

Add AppRunner targets following Lambda pattern:

```makefile
# Test individual AppRunner service
# Usage: make test-apprunner-web, make test-apprunner-admin, etc.
test-apprunner-%:
	@echo "🧪 Testing AppRunner service: $*..."
	./scripts/test-apprunner.sh $*

# Docker build/push for specific AppRunner service
# Usage: make docker-push-apprunner-web-dev
docker-push-apprunner-%-dev:
	@echo "📤 Building and pushing AppRunner image for service: $*..."
	./scripts/docker-push.sh dev $* Dockerfile.apprunner

docker-push-apprunner-%-prod:
	@echo "📤 Building and pushing AppRunner image for service: $*..."
	./scripts/docker-push.sh prod $* Dockerfile.apprunner
```

### Phase 4: Update README.md

Add multi-AppRunner examples:

```markdown
## Multi-Service AppRunner Deployment

### Create Multiple AppRunner Services

```bash
# Create web frontend service
./scripts/setup-terraform-apprunner.sh web

# Create admin dashboard service
./scripts/setup-terraform-apprunner.sh admin

# Create API service (alternative to Lambda)
./scripts/setup-terraform-apprunner.sh api
```

### Build and Deploy

```bash
# Build images for each service
./scripts/docker-push.sh dev web Dockerfile.apprunner
./scripts/docker-push.sh dev admin Dockerfile.apprunner

# Deploy all services
make app-init-dev app-apply-dev
```

### Test Services

```bash
# Test individual services
make test-apprunner-web
make test-apprunner-admin
./scripts/test-apprunner.sh api
```
```

## File Structure After Implementation

```
terraform/
├── main.tf                    # Shared (created once)
├── variables.tf               # Shared (created once)
├── api-gateway.tf             # Shared API Gateway (from separate refactoring)
├── apprunner-web.tf           # Web service
├── apprunner-admin.tf         # Admin service
├── apprunner-api.tf           # API service (alternative to Lambda)
└── environments/
    ├── dev.tfvars             # Shared (created once)
    ├── test.tfvars            # Shared (created once)
    └── prod.tfvars            # Shared (created once)
```

## AppRunner Service Template Structure

Each `apprunner-<service>.tf` file will contain:

```hcl
# =============================================================================
# App Runner Service Configuration: <SERVICE_NAME>
# =============================================================================
# Generated by scripts/setup-terraform-apprunner.sh
# This file defines the App Runner service for the <SERVICE_NAME> service
# =============================================================================

# IAM role for App Runner service (from bootstrap)
data "aws_iam_role" "apprunner_execution_<SERVICE>" {
  name = "${var.project_name}-apprunner-execution-role"
}

data "aws_iam_role" "apprunner_instance_<SERVICE>" {
  name = "${var.project_name}-apprunner-instance-role"
}

# App Runner service using container image
resource "aws_apprunner_service" "<SERVICE>" {
  service_name = "${var.project_name}-${var.environment}-<SERVICE>"

  source_configuration {
    image_repository {
      image_identifier      = "${data.aws_ecr_repository.app.repository_url}:<SERVICE>-${var.environment}-latest"
      image_repository_type = "ECR"
      image_configuration {
        port = "8080"
        runtime_environment_variables = {
          ENVIRONMENT  = var.environment
          PROJECT_NAME = var.project_name
          SERVICE_NAME = "<SERVICE>"
          LOG_LEVEL    = var.environment == "prod" ? "INFO" : "DEBUG"
        }
      }
    }
    authentication_configuration {
      access_role_arn = data.aws_iam_role.apprunner_execution_<SERVICE>.arn
    }
    auto_deployments_enabled = true
  }

  instance_configuration {
    instance_role_arn = data.aws_iam_role.apprunner_instance_<SERVICE>.arn
    cpu               = var.apprunner_cpu
    memory            = var.apprunner_memory
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-<SERVICE>"
    Service     = "<SERVICE>"
    Description = "<SERVICE> App Runner service"
  }
}

# =============================================================================
# Outputs for <SERVICE> Service
# =============================================================================

output "apprunner_<SERVICE>_url" {
  description = "App Runner service URL for <SERVICE>"
  value       = "https://${aws_apprunner_service.<SERVICE>.service_url}"
}

output "apprunner_<SERVICE>_arn" {
  description = "ARN of the <SERVICE> App Runner service"
  value       = aws_apprunner_service.<SERVICE>.arn
}

output "apprunner_<SERVICE>_status" {
  description = "Status of the <SERVICE> App Runner service"
  value       = aws_apprunner_service.<SERVICE>.status
}
```

## Benefits

✅ **Multiple AppRunner Services** - Deploy web, admin, api, etc.
✅ **Consistent Pattern** - Same approach as Lambda multi-service
✅ **Service Isolation** - Each service in its own file
✅ **Independent Scaling** - Each service scales independently
✅ **Clear Naming** - `apprunner-<service>.tf` pattern
✅ **Easy Testing** - `make test-apprunner-<service>`

## Migration Path for Existing Users

For users with existing `apprunner.tf`:

```bash
# Rename existing file to follow new pattern
mv terraform/apprunner.tf terraform/apprunner-apprunner.tf

# Or rename to specific service
mv terraform/apprunner.tf terraform/apprunner-web.tf

# Update resource names in the file
# Change: aws_apprunner_service.app → aws_apprunner_service.web
```

## Implementation Order

1. ✅ Analyze Lambda multi-service pattern
2. ✅ Create implementation plan (this document)
3. Update `setup-terraform-apprunner.sh` script
4. Create `test-apprunner.sh` script
5. Update `Makefile` with AppRunner targets
6. Update `README.md` with multi-AppRunner examples
7. Test with multiple AppRunner services
8. Document migration path for existing users

## Testing Checklist

- [ ] Create first AppRunner service (should create shared files)
- [ ] Create second AppRunner service (should not overwrite shared files)
- [ ] Deploy both services
- [ ] Test both services with `test-apprunner.sh`
- [ ] Test Makefile targets (`make test-apprunner-web`)
- [ ] Verify outputs in Terraform
- [ ] Test service-to-service communication

## Related Work

This work is a prerequisite for the API Gateway refactoring (see [API_GATEWAY_REFACTORING_PLAN.md](./API_GATEWAY_REFACTORING_PLAN.md)):
- Multi-Lambda services ✅ Implemented
- Multi-AppRunner services ⏳ In Progress
- Multi-service API Gateway ⏸️ Waiting for AppRunner completion
