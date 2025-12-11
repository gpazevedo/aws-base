#!/bin/bash
# =============================================================================
# Generate App Runner Service Terraform Configuration
# =============================================================================
# This script creates Terraform files for deploying App Runner services.
# It creates apprunner-variables.tf (if it doesn't exist) with AppRunner-specific
# variables, and creates apprunner-{service}.tf for each service.
#
# Prerequisites: Run ./scripts/setup-terraform-base.sh first
#
# Usage: ./scripts/setup-terraform-apprunner.sh [SERVICE_NAME] [S3VECTOR_BUCKETS]
#
# Arguments:
#   SERVICE_NAME      - Name of the service (default: runner)
#   S3VECTOR_BUCKETS  - Comma-separated list of S3 vector bucket suffixes
#                       (default: vector-embeddings)
#                       Only used when enable_s3vector=true in bootstrap
#
# Examples:
#   ./scripts/setup-terraform-apprunner.sh web
#   ./scripts/setup-terraform-apprunner.sh admin "vector-embeddings,vector-cache"
#   ./scripts/setup-terraform-apprunner.sh runner
# =============================================================================

set -e

# Parse command line arguments
SERVICE_NAME="${1:-runner}"  # Default: 'runner' for backward compatibility
S3VECTOR_BUCKETS="${2:-vector-embeddings}"  # Default: 'vector-embeddings'

TERRAFORM_DIR="terraform"
BOOTSTRAP_DIR="bootstrap"
ENVIRONMENTS=("dev" "test" "prod")

echo "🚀 Setting up App Runner service Terraform configuration..."
echo ""

# =============================================================================
# Validate Service Directory
# =============================================================================

# Check if service directory exists in backend/
if [ ! -d "backend/${SERVICE_NAME}" ]; then
  echo "❌ Error: Service directory not found: backend/${SERVICE_NAME}"
  echo ""
  echo "Available services in backend/:"
  ls -d backend/*/ 2>/dev/null | xargs -n1 basename | grep -v "^$" || echo "  None found"
  echo ""
  echo "To create a new service, first create the directory:"
  echo "  mkdir -p backend/${SERVICE_NAME}"
  echo "  cp -r backend/runner/* backend/${SERVICE_NAME}/"
  echo "  # Then customize backend/${SERVICE_NAME}/main.py for your service"
  exit 1
fi

echo "✅ Service directory found: backend/${SERVICE_NAME}"
echo ""

# =============================================================================
# Check Prerequisites
# =============================================================================

# Check if base Terraform files exist
if [ ! -f "$TERRAFORM_DIR/main.tf" ] || [ ! -f "$TERRAFORM_DIR/variables.tf" ]; then
  echo "❌ Error: Base Terraform configuration not found"
  echo ""
  echo "Please run setup-terraform-base.sh first:"
  echo "  ./scripts/setup-terraform-base.sh"
  echo ""
  exit 1
fi

# =============================================================================
# Check Bootstrap Configuration
# =============================================================================

if [ ! -f "$BOOTSTRAP_DIR/terraform.tfvars" ]; then
  echo "⚠️  Warning: Bootstrap terraform.tfvars not found"
  echo "   Using default values for examples"
  echo "   You should run bootstrap first: cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars"
  echo ""
  PROJECT_NAME="<YOUR-PROJECT>"
  AWS_REGION="us-east-1"
else
  # Read configuration from bootstrap
  PROJECT_NAME=$(grep '^project_name' "$BOOTSTRAP_DIR/terraform.tfvars" | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "')
  AWS_REGION=$(grep '^aws_region' "$BOOTSTRAP_DIR/terraform.tfvars" | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "')
  GITHUB_ORG=$(grep '^github_org' "$BOOTSTRAP_DIR/terraform.tfvars" | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "')
  GITHUB_REPO=$(grep '^github_repo' "$BOOTSTRAP_DIR/terraform.tfvars" | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "')
  ENABLE_S3VECTOR=$(grep '^enable_s3vector' "$BOOTSTRAP_DIR/terraform.tfvars" | cut -d'=' -f2 | cut -d'#' -f1 | tr -d ' "')
fi

# Set defaults if not found
: ${GITHUB_ORG:="<YOUR-ORG>"}
: ${GITHUB_REPO:="<YOUR-REPO>"}

echo "📋 Configuration:"
echo "   Service: $SERVICE_NAME"
echo "   Project: $PROJECT_NAME"
echo "   Region: $AWS_REGION"
echo "   GitHub: $GITHUB_ORG/$GITHUB_REPO"
if [ "$ENABLE_S3VECTOR" = "true" ]; then
  echo "   S3 Vector: Enabled"
  echo "   Buckets: $S3VECTOR_BUCKETS"
fi
echo ""

# =============================================================================
# Create apprunner-variables.tf (AppRunner-Specific Variables Only)
# =============================================================================
APPRUNNER_VARS_FILE="$TERRAFORM_DIR/apprunner-variables.tf"

if [ ! -f "$APPRUNNER_VARS_FILE" ]; then
  echo "📝 Creating terraform/apprunner-variables.tf..."
  cat > "$APPRUNNER_VARS_FILE" <<'EOF'
# =============================================================================
# App Runner Service Variables
# =============================================================================
# Generated by scripts/setup-terraform-apprunner.sh
# These variables are specific to App Runner services
# Common variables are in variables.tf
# =============================================================================

variable "apprunner_cpu" {
  description = "Default App Runner CPU units (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "256"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096"], var.apprunner_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096"
  }
}

variable "apprunner_memory" {
  description = "Default App Runner memory in MB (512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288)"
  type        = string
  default     = "512"

  validation {
    condition     = contains(["512", "1024", "2048", "3072", "4096", "6144", "8192", "10240", "12288"], var.apprunner_memory)
    error_message = "Memory must be one of: 512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288"
  }
}

variable "apprunner_port" {
  description = "Default port your application listens on"
  type        = number
  default     = 8080
}

variable "apprunner_min_instances" {
  description = "Default minimum number of App Runner instances"
  type        = number
  default     = 0     # 0 means scale to zero (cold starts allowed)
}

variable "apprunner_max_instances" {
  description = "Default maximum number of App Runner instances"
  type        = number
  default     = 2
}

variable "apprunner_max_concurrency" {
  description = "Default maximum concurrent requests per instance"
  type        = number
  default     = 100
}

# Health Check Configuration
variable "health_check_path" {
  description = "Default health check endpoint path"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Default health check interval in seconds"
  type        = number
  default     = 10
}

variable "health_check_timeout" {
  description = "Default health check timeout in seconds"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Default number of consecutive successful health checks"
  type        = number
  default     = 1
}

variable "health_check_unhealthy_threshold" {
  description = "Default number of consecutive failed health checks"
  type        = number
  default     = 5
}

# =============================================================================
# Per-Service AppRunner Configuration (Optional)
# =============================================================================
# Use this to configure different settings for each AppRunner service
# If not provided, defaults above will be used

variable "apprunner_service_configs" {
  description = "Per-service AppRunner configuration"
  type = map(object({
    cpu             = optional(string)
    memory          = optional(string)
    port            = optional(number)
    min_instances   = optional(number)
    max_instances   = optional(number)
    max_concurrency = optional(number)
    health_check_path = optional(string)
  }))
  default = {}
}

# Example usage in environments/{env}.tfvars:
#
# apprunner_service_configs = {
#   web = {
#     cpu             = "1024"
#     memory          = "2048"
#     port            = 8080
#     min_instances   = 2
#     max_instances   = 10
#     max_concurrency = 200
#   }
#   admin = {
#     cpu             = "512"
#     memory          = "1024"
#     port            = 8080
#     min_instances   = 1
#     max_instances   = 3
#     max_concurrency = 100
#   }
#   worker = {
#     cpu             = "2048"
#     memory          = "4096"
#     port            = 8080
#     min_instances   = 1
#     max_instances   = 5
#     max_concurrency = 50
#   }
# }
EOF
  echo "✅ Created terraform/apprunner-variables.tf"
else
  echo "ℹ️  AppRunner variables file already exists (terraform/apprunner-variables.tf)"
fi

# =============================================================================
# Update environment tfvars with AppRunner-specific defaults
# =============================================================================
for ENV in "${ENVIRONMENTS[@]}"; do
  TFVARS_FILE="$TERRAFORM_DIR/environments/${ENV}.tfvars"

  if [ -f "$TFVARS_FILE" ]; then
    # Check if AppRunner variables are already present
    if ! grep -q "^apprunner_cpu" "$TFVARS_FILE" 2>/dev/null; then
      echo "📝 Adding AppRunner variables to $TFVARS_FILE..."

      cat >> "$TFVARS_FILE" <<EOF

# =============================================================================
# App Runner Configuration
# =============================================================================

apprunner_cpu            = "$([ "$ENV" = "prod" ] && echo "2048" || echo "1024")"
apprunner_memory         = "$([ "$ENV" = "prod" ] && echo "4096" || echo "2048")"
apprunner_port           = 8080
apprunner_min_instances  = $([ "$ENV" = "prod" ] && echo "2" || echo "1")
apprunner_max_instances  = $([ "$ENV" = "prod" ] && echo "10" || echo "5")
apprunner_max_concurrency = $([ "$ENV" = "prod" ] && echo "200" || echo "100")

# Health Check
health_check_path                = "/health"
health_check_interval            = 10
health_check_timeout             = 5
health_check_healthy_threshold   = 1
health_check_unhealthy_threshold = 5

# Per-service AppRunner configuration (optional)
# apprunner_service_configs = {
#   web = {
#     cpu             = "1024"
#     memory          = "2048"
#     port            = 8080
#     min_instances   = 2
#     max_instances   = 10
#     max_concurrency = 200
#   }
#   admin = {
#     cpu             = "512"
#     memory          = "1024"
#     port            = 8001
#     min_instances   = 1
#     max_instances   = 3
#     max_concurrency = 100
#   }
# }
EOF
    else
      echo "ℹ️  AppRunner variables already present in $TFVARS_FILE"
    fi
  fi
done

# =============================================================================
# Generate S3 Vector Configuration (if enabled)
# =============================================================================
S3VECTOR_DATA_BLOCK=""
S3VECTOR_POLICY_ATTACHMENTS=""
S3VECTOR_ENV_VARS=""

if [ "$ENABLE_S3VECTOR" = "true" ]; then
  echo "📦 S3 Vector storage enabled - generating configuration..."

  # Parse bucket suffixes into array
  IFS=',' read -ra BUCKET_ARRAY <<< "$S3VECTOR_BUCKETS"

  # Generate data source for bootstrap remote state
  S3VECTOR_DATA_BLOCK="# =============================================================================
# S3 Vector Storage Configuration (Bootstrap Remote State)
# =============================================================================

data \"terraform_remote_state\" \"bootstrap\" {
  backend = \"s3\"
  config = {
    bucket = \"\${var.project_name}-terraform-state-\${data.aws_caller_identity.current.account_id}\"
    key    = \"bootstrap/terraform.tfstate\"
    region = var.aws_region
  }
}

data \"aws_caller_identity\" \"current\" {}

"

  # Generate policy attachments
  S3VECTOR_POLICY_ATTACHMENTS="
# Attach S3 Vector and Bedrock policies to AppRunner instance role
resource \"aws_iam_role_policy_attachment\" \"${SERVICE_NAME}_s3_vectors\" {
  role       = data.aws_iam_role.apprunner_instance_${SERVICE_NAME}.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
}

resource \"aws_iam_role_policy_attachment\" \"${SERVICE_NAME}_bedrock\" {
  role       = data.aws_iam_role.apprunner_instance_${SERVICE_NAME}.name
  policy_arn = data.terraform_remote_state.bootstrap.outputs.bedrock_invocation_policy_arn
}

"

  # Generate environment variables based on number of buckets
  if [ ${#BUCKET_ARRAY[@]} -eq 1 ]; then
    # Single bucket - use VECTOR_BUCKET_NAME for backward compatibility
    S3VECTOR_ENV_VARS="
            # S3 Vector Storage Configuration
            VECTOR_BUCKET_NAME = data.terraform_remote_state.bootstrap.outputs.s3_vector_bucket_ids[\"${BUCKET_ARRAY[0]}\"]
            BEDROCK_MODEL_ID   = \"amazon.titan-embed-text-v2:0\"
"
  else
    # Multiple buckets - use {SUFFIX_UPPERCASE}_BUCKET naming
    S3VECTOR_ENV_VARS="
            # S3 Vector Storage Configuration"
    for bucket in "${BUCKET_ARRAY[@]}"; do
      # Convert bucket suffix to uppercase with underscores (e.g., "vector-embeddings" -> "VECTOR_EMBEDDINGS")
      BUCKET_VAR_NAME=$(echo "${bucket}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
      S3VECTOR_ENV_VARS="${S3VECTOR_ENV_VARS}
            ${BUCKET_VAR_NAME}_BUCKET = data.terraform_remote_state.bootstrap.outputs.s3_vector_bucket_ids[\"${bucket}\"]"
    done
    S3VECTOR_ENV_VARS="${S3VECTOR_ENV_VARS}
            BEDROCK_MODEL_ID   = \"amazon.titan-embed-text-v2:0\"
"
  fi

  echo "✅ S3 Vector configuration generated for buckets: ${S3VECTOR_BUCKETS}"
fi

# =============================================================================
# Create apprunner-{service}.tf
# =============================================================================
APPRUNNER_TF_FILE="$TERRAFORM_DIR/apprunner-${SERVICE_NAME}.tf"

# Check if file already exists
if [ -f "$APPRUNNER_TF_FILE" ]; then
  echo "⚠️  Warning: ${APPRUNNER_TF_FILE} already exists"
  read -p "Overwrite? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping apprunner-${SERVICE_NAME}.tf generation"
    echo "✅ Setup completed (existing files preserved)"
    exit 0
  fi
fi

echo "📝 Creating ${APPRUNNER_TF_FILE}..."
cat > "$APPRUNNER_TF_FILE" <<TEMPLATE_EOF
# =============================================================================
# App Runner Service Configuration: ${SERVICE_NAME}
# =============================================================================
# Generated by scripts/setup-terraform-apprunner.sh
# This file defines the App Runner service for the ${SERVICE_NAME} service
# =============================================================================

${S3VECTOR_DATA_BLOCK}

# Service-specific configuration
# Edit these values to customize this App Runner service
locals {
  ${SERVICE_NAME}_config = {
    cpu             = "1024"
    memory          = "2048"
    port            = 8080
    min_instances   = 1
    max_instances   = 5
    max_concurrency = 100
    health_check_path = "/health"
    # Add service-specific environment variables here
    environment_variables = {
      # KEY = "value"
    }
  }

  # Service API Key configuration
  # Defines the API key for this service when enable_service_api_keys = true
  ${SERVICE_NAME}_service_api_key = \${var.enable_service_api_keys} ? {
    ${SERVICE_NAME} = {
      quota_limit  = 100000
      quota_period = "MONTH"
      description  = "${SERVICE_NAME} service"
    }
  } : {}
}

# Get App Runner IAM roles from bootstrap
data "aws_iam_role" "apprunner_access_${SERVICE_NAME}" {
  name = "\${var.project_name}-apprunner-access"
}

data "aws_iam_role" "apprunner_instance_${SERVICE_NAME}" {
  name = "\${var.project_name}-apprunner-instance"
}

${S3VECTOR_POLICY_ATTACHMENTS}

# IAM policy for Secrets Manager access (API key retrieval)
resource "aws_iam_role_policy" "${SERVICE_NAME}_secrets_access" {
  count = \${var.enable_service_api_keys} ? 1 : 0

  name = "\${var.project_name}-\${var.environment}-${SERVICE_NAME}-secrets"
  role = data.aws_iam_role.apprunner_instance_${SERVICE_NAME}.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        "arn:aws:secretsmanager:\${var.aws_region}:*:secret:\${var.project_name}/\${var.environment}/${SERVICE_NAME}/api-key-*"
      ]
    }]
  })
}

# Observability Configuration (OpenTelemetry via X-Ray)
# Note: AWS X-Ray supports OTLP traces from OpenTelemetry
resource "aws_apprunner_observability_configuration" "${SERVICE_NAME}" {
  observability_configuration_name = "\${var.project_name}-\${var.environment}-${SERVICE_NAME}-obs"

  trace_configuration {
    vendor = "AWSXRAY"
  }

  tags = {
    Name    = "\${var.project_name}-\${var.environment}-${SERVICE_NAME}-obs"
    Service = "${SERVICE_NAME}"
  }
}

# App Runner Service
resource "aws_apprunner_service" "${SERVICE_NAME}" {
  service_name = "\${var.project_name}-\${var.environment}-${SERVICE_NAME}"

  source_configuration {
    image_repository {
      image_identifier      = "\${data.aws_ecr_repository.app.repository_url}:${SERVICE_NAME}-\${var.environment}-latest"
      image_repository_type = "ECR"

      image_configuration {
        # Port - uses local config
        port = local.${SERVICE_NAME}_config.port

        runtime_environment_variables = merge(
          {
            ENVIRONMENT     = \${var.environment}
            PROJECT_NAME    = \${var.project_name}
            SERVICE_NAME    = "${SERVICE_NAME}"
            LOG_LEVEL       = \${var.environment} == "prod" ? "INFO" : "DEBUG"

            # ADOT/OpenTelemetry Configuration for X-Ray Tracing
            # App Runner manages the OTLP collector on localhost:4317
            # See: https://docs.aws.amazon.com/apprunner/latest/dg/monitor-xray.html
            OTEL_PROPAGATORS                      = "xray"
            OTEL_PYTHON_ID_GENERATOR              = "xray"
            OTEL_METRICS_EXPORTER                 = "none"  # App Runner only accepts traces, not metrics
            OTEL_EXPORTER_OTLP_ENDPOINT           = "http://localhost:4317"
            OTEL_RESOURCE_ATTRIBUTES              = "service.name=${SERVICE_NAME}"
            OTEL_SERVICE_NAME                     = "${SERVICE_NAME}"
            OTEL_PYTHON_DISABLED_INSTRUMENTATIONS = "urllib3"  # Reduce noise from low-level HTTP${S3VECTOR_ENV_VARS}
          },
          local.${SERVICE_NAME}_config.environment_variables
        )
      }
    }

    authentication_configuration {
      access_role_arn = data.aws_iam_role.apprunner_access_${SERVICE_NAME}.arn
    }

    auto_deployments_enabled = false
  }

  instance_configuration {
    # CPU and Memory - uses local config
    cpu    = local.${SERVICE_NAME}_config.cpu
    memory = local.${SERVICE_NAME}_config.memory

    instance_role_arn = data.aws_iam_role.apprunner_instance_${SERVICE_NAME}.arn
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = local.${SERVICE_NAME}_config.health_check_path
    interval            = \${var.health_check_interval}
    timeout             = \${var.health_check_timeout}
    healthy_threshold   = \${var.health_check_healthy_threshold}
    unhealthy_threshold = \${var.health_check_unhealthy_threshold}
  }

  # Observability configuration (distributed tracing)
  observability_configuration {
    observability_enabled           = true
    observability_configuration_arn = aws_apprunner_observability_configuration.${SERVICE_NAME}.arn
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.${SERVICE_NAME}.arn

  tags = {
    Name        = "\${var.project_name}-\${var.environment}-${SERVICE_NAME}"
    Service     = "${SERVICE_NAME}"
    Description = "${SERVICE_NAME} App Runner service"
  }
}

# Auto Scaling Configuration
resource "aws_apprunner_auto_scaling_configuration_version" "${SERVICE_NAME}" {
  auto_scaling_configuration_name = "\${var.project_name}-\${var.environment}-${SERVICE_NAME}-as"

  # Uses local config
  min_size        = local.${SERVICE_NAME}_config.min_instances
  max_size        = local.${SERVICE_NAME}_config.max_instances
  max_concurrency = local.${SERVICE_NAME}_config.max_concurrency

  tags = {
    Name    = "\${var.project_name}-\${var.environment}-${SERVICE_NAME}-as"
    Service = "${SERVICE_NAME}"
  }
}

# =============================================================================
# Outputs for ${SERVICE_NAME} Service
# =============================================================================

output "apprunner_${SERVICE_NAME}_service_id" {
  description = "ID of the ${SERVICE_NAME} App Runner service"
  value       = aws_apprunner_service.${SERVICE_NAME}.service_id
}

output "apprunner_${SERVICE_NAME}_service_arn" {
  description = "ARN of the ${SERVICE_NAME} App Runner service"
  value       = aws_apprunner_service.${SERVICE_NAME}.arn
}

output "apprunner_${SERVICE_NAME}_url" {
  description = "App Runner service URL for ${SERVICE_NAME}"
  value       = "https://\${aws_apprunner_service.${SERVICE_NAME}.service_url}"
}

output "apprunner_${SERVICE_NAME}_status" {
  description = "Status of the ${SERVICE_NAME} App Runner service"
  value       = aws_apprunner_service.${SERVICE_NAME}.status
}
TEMPLATE_EOF

# =============================================================================
# API Gateway Integration (Optional)
# =============================================================================
API_GATEWAY_FILE="$TERRAFORM_DIR/api-gateway.tf"

if [ -f "$API_GATEWAY_FILE" ]; then
  echo ""
  echo "📝 API Gateway configuration found"
  echo ""
  read -p "Do you want to add '${SERVICE_NAME}' to API Gateway? (y/N): " -n 1 -r
  echo

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check if AppRunner integrations section exists
    if ! grep -q "# AppRunner Service Integrations" "$API_GATEWAY_FILE"; then
      echo "📝 Adding AppRunner integrations section to api-gateway.tf..."
      cat >> "$API_GATEWAY_FILE" <<'EOF'

# =============================================================================
# AppRunner Service Integrations
# =============================================================================

EOF
    fi

    # Check if this service integration already exists
    if grep -q "module \"api_gateway_apprunner_${SERVICE_NAME}\"" "$API_GATEWAY_FILE"; then
      echo "ℹ️  Integration for '${SERVICE_NAME}' already exists in api-gateway.tf"
    else
      echo "📝 Appending integration for '${SERVICE_NAME}' to api-gateway.tf..."

      cat >> "$API_GATEWAY_FILE" <<EOF

# Integration for '${SERVICE_NAME}' AppRunner service
module "api_gateway_apprunner_${SERVICE_NAME}" {
  source = "./modules/api-gateway-apprunner-integration"
  count  = local.api_gateway_enabled ? 1 : 0

  service_name = "${SERVICE_NAME}"
  path_prefix  = "${SERVICE_NAME}"  # /${SERVICE_NAME}, /${SERVICE_NAME}/*

  api_id                = module.api_gateway_shared[0].api_id
  api_root_resource_id  = module.api_gateway_shared[0].root_resource_id
  api_execution_arn     = module.api_gateway_shared[0].execution_arn

  apprunner_service_url = aws_apprunner_service.${SERVICE_NAME}.service_url

  api_key_required      = var.enable_api_key
}
EOF

      echo "✅ Added integration module for '${SERVICE_NAME}'"

      # =============================================================================
      # Update service_api_keys merge block (for per-service API keys)
      # =============================================================================
      echo "📝 Updating service_api_keys merge block..."

      # Check if service_api_keys merge block exists
      if grep -q "service_api_keys.*=.*merge(" "$API_GATEWAY_FILE"; then
        # Check if this service is already in the merge block
        if ! grep -q "local.${SERVICE_NAME}_service_api_key" "$API_GATEWAY_FILE"; then
          # Find the merge block and add the new service
          awk -v service="${SERVICE_NAME}" '
            /service_api_keys.*=.*merge\(/ {
              # Found the start of merge block
              in_merge_block = 1
              print $0
              next
            }
            in_merge_block && /^[[:space:]]*\)/ {
              # End of merge block, add new service before closing paren
              print "    local." service "_service_api_key,"
              in_merge_block = 0
              print $0
              next
            }
            { print $0 }
          ' "$API_GATEWAY_FILE" > "${API_GATEWAY_FILE}.tmp"

          mv "${API_GATEWAY_FILE}.tmp" "$API_GATEWAY_FILE"
          echo "✅ Added '${SERVICE_NAME}' to service_api_keys merge block"
        else
          echo "ℹ️  '${SERVICE_NAME}' already in service_api_keys merge block"
        fi
      else
        echo "⚠️  service_api_keys merge block not found in api-gateway.tf"
        echo "   You may need to manually add: local.${SERVICE_NAME}_service_api_key"
      fi

      # =============================================================================
      # Update api_gateway_shared module to include integration_ids
      # =============================================================================
      echo "📝 Updating api_gateway_shared module with integration dependencies..."

      # Check if integration_ids already exists in the shared module
      if grep -q "integration_ids.*=" "$API_GATEWAY_FILE"; then
        # integration_ids line already exists, we need to add this service to the list
        # Create a temporary file with the updated integration_ids
        awk -v service="${SERVICE_NAME}" '
          /integration_ids.*=.*\[/ {
            # Found the start of integration_ids list
            in_integration_list = 1
            print $0
            next
          }
          in_integration_list && /\]/ {
            # End of integration_ids list, add new service before closing bracket
            print "    module.api_gateway_apprunner_" service "[0].integration_id,"
            in_integration_list = 0
            print $0
            next
          }
          { print $0 }
        ' "$API_GATEWAY_FILE" > "${API_GATEWAY_FILE}.tmp"

        mv "${API_GATEWAY_FILE}.tmp" "$API_GATEWAY_FILE"
        echo "✅ Added '${SERVICE_NAME}' to existing integration_ids list"
      else
        # integration_ids doesn't exist, add it to the shared module
        awk -v service="${SERVICE_NAME}" '
          /^module "api_gateway_shared"/ {
            in_shared_module = 1
          }
          in_shared_module && /count.*=.*local.api_gateway_enabled/ {
            print $0
            print ""
            print "  # Integration IDs for deployment dependencies"
            print "  # This ensures the deployment waits for all integrations to be created"
            print "  integration_ids = local.api_gateway_enabled ? ["
            print "    module.api_gateway_apprunner_" service "[0].integration_id,"
            print "  ] : []"
            in_shared_module = 0
            next
          }
          { print $0 }
        ' "$API_GATEWAY_FILE" > "${API_GATEWAY_FILE}.tmp"

        mv "${API_GATEWAY_FILE}.tmp" "$API_GATEWAY_FILE"
        echo "✅ Added integration_ids to api_gateway_shared module"
      fi
    fi
  else
    echo "ℹ️  Skipping API Gateway integration"
    echo "   Service will be accessible directly via AppRunner URL"
  fi
else
  echo "ℹ️  API Gateway not configured"
  echo "   Service will be accessible directly via AppRunner URL"
fi

echo ""
echo "✅ App Runner service '${SERVICE_NAME}' Terraform configuration created successfully!"
echo ""
echo "📂 Created/Updated files:"
echo "   terraform/apprunner-variables.tf"
echo "   terraform/apprunner-${SERVICE_NAME}.tf ✨"
if [ -f "$API_GATEWAY_FILE" ]; then
  echo "   terraform/api-gateway.tf (optionally updated)"
fi
for ENV in "${ENVIRONMENTS[@]}"; do
  if [ -f "$TERRAFORM_DIR/environments/${ENV}.tfvars" ]; then
    echo "   terraform/environments/${ENV}.tfvars (updated)"
  fi
done
echo ""
if [ "$ENABLE_S3VECTOR" = "true" ]; then
  echo "📦 S3 Vector Storage Configuration:"
  echo "   ✅ Bootstrap remote state data source configured"
  echo "   ✅ IAM policies attached: S3 Vector + Bedrock"
  echo "   ✅ Buckets: ${S3VECTOR_BUCKETS}"

  # Parse bucket suffixes into array for display
  IFS=',' read -ra BUCKET_ARRAY <<< "$S3VECTOR_BUCKETS"
  if [ ${#BUCKET_ARRAY[@]} -eq 1 ]; then
    echo "   ✅ Environment variable: VECTOR_BUCKET_NAME"
  else
    echo "   ✅ Environment variables:"
    for bucket in "${BUCKET_ARRAY[@]}"; do
      BUCKET_VAR_NAME=$(echo "${bucket}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
      echo "      - ${BUCKET_VAR_NAME}_BUCKET"
    done
  fi
  echo "   ✅ Bedrock model: amazon.titan-embed-text-v2:0"
  echo ""
fi
echo "🔭 Observability Features:"
echo "   ✅ ADOT (AWS Distro for OpenTelemetry) in-container instrumentation"
echo "   ✅ Automatic tracing for FastAPI, boto3, httpx"
echo "   ✅ X-Ray integration via App Runner observability config"
echo "   ✅ JSON structured logging"
echo ""
echo "🚀 Next Steps for '${SERVICE_NAME}' Service:"
echo ""
echo "1. Build and push Docker image:"
echo "   ./scripts/docker-push.sh dev ${SERVICE_NAME} Dockerfile.apprunner"
echo ""
echo "2. Deploy infrastructure:"
echo "   make app-init-dev app-apply-dev"
echo ""
echo "3. Test the deployed service:"
echo "   APPRUNNER_URL=\$(cd terraform && terraform output -raw apprunner_${SERVICE_NAME}_url)"
echo "   curl \$APPRUNNER_URL/health"
echo ""
echo "💡 To configure service-specific settings (CPU, memory, scaling, etc.):"
echo "   Edit terraform/environments/dev.tfvars and add to apprunner_service_configs"
echo ""
echo "🔧 ADOT Configuration:"
echo "   - ADOT is installed in the container image (Dockerfile.apprunner)"
echo "   - Environment variables configured for X-Ray tracing"
echo "   - App Runner manages the OTLP collector on localhost:4317"
echo "   - Update versions: Edit adot_python_version in apprunner-variables.tf"
echo ""
echo "🔑 API Keys:"
echo "   - Service API key configuration is in locals.${SERVICE_NAME}_service_api_key"
echo "   - Enable with: enable_service_api_keys = true in tfvars"
echo "   - Get API key: terraform output -json service_api_key_values | jq -r '.${SERVICE_NAME}'"
echo "   - See docs/API-KEYS-QUICKSTART.md for usage in code"
echo ""
