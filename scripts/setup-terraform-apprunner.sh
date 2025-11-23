#!/bin/bash
# =============================================================================
# Generate App Runner Service Terraform Configuration
# =============================================================================
# This script creates Terraform files for deploying App Runner services
# in the terraform/ directory with environment-specific configurations
#
# Usage: ./scripts/setup-terraform-apprunner.sh [SERVICE_NAME] [ENABLE_API_KEY]
#
# Examples:
#   ./scripts/setup-terraform-apprunner.sh web false         # Create apprunner-web.tf
#   ./scripts/setup-terraform-apprunner.sh admin true        # Create apprunner-admin.tf
#   ./scripts/setup-terraform-apprunner.sh                   # Create apprunner-apprunner.tf (default)
# =============================================================================

set -e

# Parse command line arguments
SERVICE_NAME="${1:-apprunner}"  # Default: 'apprunner' for backward compatibility
ENABLE_API_KEY="${2:-true}"     # Default: enabled

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
  echo "  cp -r backend/apprunner/* backend/${SERVICE_NAME}/"
  echo "  # Then customize backend/${SERVICE_NAME}/main.py for your service"
  exit 1
fi

echo "✅ Service directory found: backend/${SERVICE_NAME}"
echo ""

# =============================================================================
# Check Bootstrap Configuration
# =============================================================================

# Check if bootstrap has been initialized
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
fi

# Set defaults if not found
: ${GITHUB_ORG:="<YOUR-ORG>"}
: ${GITHUB_REPO:="<YOUR-REPO>"}

echo "📋 Configuration:"
echo "   Service: $SERVICE_NAME"
echo "   Project: $PROJECT_NAME"
echo "   Region: $AWS_REGION"
echo "   GitHub: $GITHUB_ORG/$GITHUB_REPO"
echo "   API Key: $ENABLE_API_KEY"
echo ""
echo "=================================================="
echo "🔑 API Key Authentication Configuration"
echo "=================================================="
if [ "$ENABLE_API_KEY" = "true" ]; then
  echo "✅ API Key authentication will be ENABLED"
  echo ""
  echo "Your API will require an API key for all requests."
  echo "After deployment, retrieve your API key with:"
  echo "  cd terraform && terraform output -raw api_key_value"
  echo ""
  echo "To disable API Key authentication, edit terraform/environments/{env}.tfvars:"
  echo "  enable_api_key = false"
else
  echo "⚠️  API Key authentication will be DISABLED"
  echo ""
  echo "Your API will be publicly accessible without authentication."
  echo "This is NOT recommended for production environments."
  echo ""
  echo "To enable API Key authentication, edit terraform/environments/{env}.tfvars:"
  echo "  enable_api_key = true"
fi
echo "=================================================="
echo ""

# Create terraform directory if it doesn't exist
mkdir -p "$TERRAFORM_DIR/environments"

# =============================================================================
# Create main.tf (only if it doesn't exist)
# =============================================================================
if [ -f "$TERRAFORM_DIR/main.tf" ]; then
  echo "⏭️  Skipping terraform/main.tf (already exists)"
else
  echo "📝 Creating terraform/main.tf..."
  cat > "$TERRAFORM_DIR/main.tf" <<'EOF'
# =============================================================================
# Application Infrastructure - Main Configuration (App Runner)
# =============================================================================
# This file defines the core infrastructure for your App Runner application
# Generated by scripts/setup-terraform-apprunner.sh
# =============================================================================

terraform {
  required_version = ">= 1.13"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration is loaded from environments/*.hcl files
  # Initialize with: terraform init -backend-config=environments/dev-backend.hcl
  backend "s3" {
    # Backend config provided via -backend-config flag
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = var.github_repo
    }
  }
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get ECR repository (created by bootstrap)
data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}
EOF
fi  # End of main.tf creation

# =============================================================================
# Create variables.tf (only if it doesn't exist)
# =============================================================================
if [ -f "$TERRAFORM_DIR/variables.tf" ]; then
  echo "⏭️  Skipping terraform/variables.tf (already exists)"
else
  echo "📝 Creating terraform/variables.tf..."
  cat > "$TERRAFORM_DIR/variables.tf" <<'EOF'
# =============================================================================
# Application Infrastructure - Variables (App Runner)
# =============================================================================

variable "project_name" {
  description = "Project name (must match bootstrap configuration)"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (org/repo)"
  type        = string
}

variable "ecr_repository_name" {
  description = "ECR repository name for App Runner container images"
  type        = string
}

# =============================================================================
# App Runner Configuration
# =============================================================================

variable "apprunner_cpu" {
  description = "App Runner CPU units (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "1024"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096"], var.apprunner_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096"
  }
}

variable "apprunner_memory" {
  description = "App Runner memory in MB (512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288)"
  type        = string
  default     = "2048"

  validation {
    condition     = contains(["512", "1024", "2048", "3072", "4096", "6144", "8192", "10240", "12288"], var.apprunner_memory)
    error_message = "Memory must be one of: 512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288"
  }
}

variable "apprunner_port" {
  description = "Port your application listens on"
  type        = number
  default     = 8000
}

variable "apprunner_min_instances" {
  description = "Minimum number of App Runner instances"
  type        = number
  default     = 1
}

variable "apprunner_max_instances" {
  description = "Maximum number of App Runner instances"
  type        = number
  default     = 10
}

variable "apprunner_max_concurrency" {
  description = "Maximum concurrent requests per instance"
  type        = number
  default     = 100
}

# Health Check Configuration
variable "health_check_path" {
  description = "Health check endpoint path"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 1
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 5
}

# =============================================================================
# API Gateway Configuration
# =============================================================================

variable "enable_api_gateway_standard" {
  description = "Enable API Gateway as standard entry point (recommended for cloud deployments)"
  type        = bool
  default     = true
}

variable "enable_direct_access" {
  description = "Enable direct access to App Runner service URL. Set to true for local development."
  type        = bool
  default     = false
}

# Legacy variable for backward compatibility
variable "enable_api_gateway" {
  description = "DEPRECATED: Use enable_api_gateway_standard instead. Enable API Gateway for App Runner services"
  type        = bool
  default     = true
}

# Rate Limiting / Throttling
variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit (requests)"
  type        = number
  default     = 5000
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 10000
}

# Logging and Monitoring
variable "api_log_retention_days" {
  description = "CloudWatch log retention for API Gateway logs (days)"
  type        = number
  default     = 7
}

variable "api_logging_level" {
  description = "API Gateway logging level (OFF, ERROR, INFO)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.api_logging_level)
    error_message = "Logging level must be OFF, ERROR, or INFO"
  }
}

variable "enable_api_data_trace" {
  description = "Enable full request/response data logging (verbose, use with caution)"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for API Gateway"
  type        = bool
  default     = false
}

# Caching
variable "enable_api_caching" {
  description = "Enable API Gateway caching"
  type        = bool
  default     = false
}

# CORS Configuration
variable "cors_allow_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "CORS allowed HTTP methods"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "CORS allowed headers"
  type        = list(string)
  default     = ["Content-Type", "Authorization", "X-Requested-With"]
}

# =============================================================================
# API Key Authentication
# =============================================================================

variable "enable_api_key" {
  description = "Enable API Key authentication for API Gateway"
  type        = bool
  default     = true
}

variable "api_key_name" {
  description = "Name for the API Key (if enabled)"
  type        = string
  default     = ""
}

variable "api_usage_plan_quota_limit" {
  description = "Maximum number of requests per period (0 = unlimited)"
  type        = number
  default     = 0
}

variable "api_usage_plan_quota_period" {
  description = "Time period for quota (DAY, WEEK, MONTH)"
  type        = string
  default     = "MONTH"

  validation {
    condition     = contains(["DAY", "WEEK", "MONTH"], var.api_usage_plan_quota_period)
    error_message = "Quota period must be DAY, WEEK, or MONTH"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
EOF
fi  # End of variables.tf creation

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
cat > "$APPRUNNER_TF_FILE" <<'TEMPLATE_EOF'
# =============================================================================
# App Runner Service Configuration: SERVICE_NAME_PLACEHOLDER
# =============================================================================
# Generated by scripts/setup-terraform-apprunner.sh
# This file defines the App Runner service for the SERVICE_NAME_PLACEHOLDER service
# =============================================================================

# Get App Runner IAM roles from bootstrap
data "aws_iam_role" "apprunner_access_SERVICE_NAME_PLACEHOLDER" {
  name = "\${var.project_name}-apprunner-access"
}

data "aws_iam_role" "apprunner_instance_SERVICE_NAME_PLACEHOLDER" {
  name = "\${var.project_name}-apprunner-instance"
}

# App Runner Service
resource "aws_apprunner_service" "SERVICE_NAME_PLACEHOLDER" {
  service_name = "\${var.project_name}-\${var.environment}-SERVICE_NAME_PLACEHOLDER"

  source_configuration {
    image_repository {
      image_identifier      = "\${data.aws_ecr_repository.app.repository_url}:SERVICE_NAME_PLACEHOLDER-\${var.environment}-latest"
      image_repository_type = "ECR"

      image_configuration {
        port = var.apprunner_port

        runtime_environment_variables = {
          ENVIRONMENT  = var.environment
          PROJECT_NAME = var.project_name
          SERVICE_NAME = "SERVICE_NAME_PLACEHOLDER"
          LOG_LEVEL    = var.environment == "prod" ? "INFO" : "DEBUG"
        }
      }
    }

    authentication_configuration {
      access_role_arn = data.aws_iam_role.apprunner_access_SERVICE_NAME_PLACEHOLDER.arn
    }

    auto_deployments_enabled = false  # Control deployments via GitHub Actions
  }

  instance_configuration {
    cpu               = var.apprunner_cpu
    memory            = var.apprunner_memory
    instance_role_arn = data.aws_iam_role.apprunner_instance_SERVICE_NAME_PLACEHOLDER.arn
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = var.health_check_path
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.SERVICE_NAME_PLACEHOLDER.arn

  tags = {
    Name        = "\${var.project_name}-\${var.environment}-SERVICE_NAME_PLACEHOLDER"
    Service     = "SERVICE_NAME_PLACEHOLDER"
    Description = "Main API App Runner service"
  }

  # Note: Container image must exist in ECR before first apply
  # Build and push with:
  #   ./scripts/docker-push.sh \${var.environment} SERVICE_NAME_PLACEHOLDER Dockerfile.apprunner
  lifecycle {
    ignore_changes = [
      source_configuration[0].image_repository[0].image_identifier  # Allow image updates without Terraform
    ]
  }
}

# Auto Scaling Configuration
resource "aws_apprunner_auto_scaling_configuration_version" "SERVICE_NAME_PLACEHOLDER" {
  auto_scaling_configuration_name = "\${var.project_name}-\${var.environment}-SERVICE_NAME_PLACEHOLDER-autoscaling"

  min_size         = var.apprunner_min_instances
  max_size         = var.apprunner_max_instances
  max_concurrency  = var.apprunner_max_concurrency

  tags = {
    Name    = "\${var.project_name}-\${var.environment}-SERVICE_NAME_PLACEHOLDER-autoscaling"
    Service = "SERVICE_NAME_PLACEHOLDER"
  }
}

# =============================================================================
# Outputs for SERVICE_NAME_PLACEHOLDER Service
# =============================================================================

output "apprunner_SERVICE_NAME_PLACEHOLDER_url" {
  description = "App Runner service URL for SERVICE_NAME_PLACEHOLDER"
  value       = "https://\${aws_apprunner_service.SERVICE_NAME_PLACEHOLDER.service_url}"
}

output "apprunner_SERVICE_NAME_PLACEHOLDER_arn" {
  description = "ARN of the SERVICE_NAME_PLACEHOLDER App Runner service"
  value       = aws_apprunner_service.SERVICE_NAME_PLACEHOLDER.arn
}

output "apprunner_SERVICE_NAME_PLACEHOLDER_status" {
  description = "Status of the SERVICE_NAME_PLACEHOLDER App Runner service"
  value       = aws_apprunner_service.SERVICE_NAME_PLACEHOLDER.status
}

output "apprunner_SERVICE_NAME_PLACEHOLDER_service_id" {
  description = "Service ID of the SERVICE_NAME_PLACEHOLDER App Runner service"
  value       = aws_apprunner_service.SERVICE_NAME_PLACEHOLDER.service_id
}
TEMPLATE_EOF

# Replace placeholders with actual service name
sed -i "s/SERVICE_NAME_PLACEHOLDER/${SERVICE_NAME}/g" "$APPRUNNER_TF_FILE"

# =============================================================================
# Optional API Gateway Integration for AppRunner
# =============================================================================
# If api-gateway.tf exists (from Lambda services), offer to add AppRunner integration

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
else
  echo "ℹ️  No API Gateway configuration found (api-gateway.tf doesn't exist)"
  echo "   AppRunner service will be accessed directly via its service URL"
fi

echo ""

# Skip the old api-gateway.tf creation
if false; then
cat > "$TERRAFORM_DIR/api-gateway.tf.disabled" <<'EOF'
# =============================================================================
# API Gateway Configuration (Optional)
# =============================================================================
# Provides API Gateway as standard entry point for App Runner service
# Uses HTTP_PROXY integration to forward requests to App Runner
# =============================================================================

locals {
  api_gateway_enabled = var.enable_api_gateway_standard || var.enable_api_gateway
}

# =============================================================================
# API Gateway Shared Module
# =============================================================================
# Creates REST API, deployment, stage, and common resources

module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"
  count  = local.api_gateway_enabled ? 1 : 0

  # Basic Configuration
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

  # API Key Authentication
  enable_api_key          = var.enable_api_key
  api_key_name            = var.api_key_name
  usage_plan_quota_limit  = var.api_usage_plan_quota_limit
  usage_plan_quota_period = var.api_usage_plan_quota_period
}

# =============================================================================
# API Gateway App Runner Integration Module
# =============================================================================
# Creates HTTP_PROXY integration to forward requests to App Runner service

module "api_gateway_apprunner" {
  source = "./modules/api-gateway-apprunner"
  count  = local.api_gateway_enabled ? 1 : 0

  # API Gateway references
  api_id                = module.api_gateway_shared[0].api_id
  api_root_resource_id  = module.api_gateway_shared[0].api_root_resource_id
  api_execution_arn     = module.api_gateway_shared[0].api_execution_arn

  # App Runner service URL (without https://)
  apprunner_service_url = aws_apprunner_service.api.service_url

  # Integration settings
  path_part              = "{proxy+}"
  http_method            = "ANY"
  authorization_type     = "NONE"
  enable_root_method     = true
  connection_type        = "INTERNET"
  api_key_required       = var.enable_api_key

  # Trigger redeployment when configuration changes
  depends_on = [
    module.api_gateway_shared
  ]
}

# =============================================================================
# API Gateway Deployment Trigger
# =============================================================================
# Redeploy API Gateway when App Runner integration changes

resource "null_resource" "api_gateway_redeploy" {
  count = local.api_gateway_enabled ? 1 : 0

  triggers = {
    apprunner_integration = module.api_gateway_apprunner[0].integration_id
  }

  provisioner "local-exec" {
    command = "echo 'API Gateway will be redeployed due to App Runner integration changes'"
  }
}
EOF
fi  # End of disabled api-gateway.tf creation

# =============================================================================
# Skip outputs.tf creation (outputs are now in apprunner-<service>.tf)
# =============================================================================
# Outputs are now included in each apprunner-<service>.tf file
echo "⏭️  Skipping terraform/outputs.tf (outputs included in service files)..."
echo ""

if false; then
cat > "$TERRAFORM_DIR/outputs.tf.disabled" <<'EOF'
# =============================================================================
# Application Infrastructure - Outputs (App Runner)
# =============================================================================

locals {
  api_gateway_enabled = var.enable_api_gateway_standard || var.enable_api_gateway
}

# =============================================================================
# App Runner Outputs
# =============================================================================

output "apprunner_service_id" {
  description = "App Runner service ID"
  value       = aws_apprunner_service.api.service_id
}

output "apprunner_service_arn" {
  description = "App Runner service ARN"
  value       = aws_apprunner_service.api.arn
}

output "apprunner_service_url" {
  description = "App Runner service URL (direct access, only when enabled)"
  value       = var.enable_direct_access ? "https://${aws_apprunner_service.api.service_url}" : "Direct access disabled - use API Gateway"
}

output "apprunner_status" {
  description = "App Runner service status"
  value       = aws_apprunner_service.api.status
}

# =============================================================================
# API Gateway Outputs
# =============================================================================

output "api_gateway_url" {
  description = "API Gateway endpoint URL (standard entry point)"
  value       = local.api_gateway_enabled ? module.api_gateway_shared[0].invoke_url : "Not enabled"
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = local.api_gateway_enabled ? module.api_gateway_shared[0].api_id : "Not enabled"
}

output "api_gateway_stage" {
  description = "API Gateway stage name"
  value       = local.api_gateway_enabled ? module.api_gateway_shared[0].stage_name : "Not enabled"
}

output "api_key_id" {
  description = "API Key ID (if enabled)"
  value       = local.api_gateway_enabled && var.enable_api_key ? module.api_gateway_shared[0].api_key_id : "Not enabled"
}

output "api_key_value" {
  description = "API Key value (sensitive, if enabled)"
  value       = local.api_gateway_enabled && var.enable_api_key ? module.api_gateway_shared[0].api_key_value : null
  sensitive   = true
}

# =============================================================================
# Common Outputs
# =============================================================================

output "ecr_repository_url" {
  description = "ECR repository URL for container images"
  value       = data.aws_ecr_repository.app.repository_url
}

output "environment" {
  description = "Current environment"
  value       = var.environment
}

output "deployment_mode" {
  description = "Current deployment mode (api-gateway-standard or direct-access)"
  value       = var.enable_api_gateway_standard ? "api-gateway-standard" : (var.enable_direct_access ? "direct-access" : "legacy-api-gateway")
}

output "primary_endpoint" {
  description = "Primary application endpoint (use this for accessing the application)"
  value = local.api_gateway_enabled ? module.api_gateway_shared[0].invoke_url : (
    var.enable_direct_access ? "https://${aws_apprunner_service.api.service_url}" : "No endpoint configured"
  )
}
EOF
fi  # End of disabled outputs.tf creation

# =============================================================================
# Create environment-specific tfvars files (only if they don't exist)
# =============================================================================
for ENV in "${ENVIRONMENTS[@]}"; do
  if [ -f "$TERRAFORM_DIR/environments/${ENV}.tfvars" ]; then
    echo "⏭️  Skipping terraform/environments/${ENV}.tfvars (already exists)"
    continue
  fi

  echo "📝 Creating terraform/environments/${ENV}.tfvars..."

  cat > "$TERRAFORM_DIR/environments/${ENV}.tfvars" <<EOF
# =============================================================================
# Application Infrastructure - ${ENV} Environment (App Runner)
# =============================================================================
# Generated by scripts/setup-terraform-apprunner.sh
# Customize these values for your ${ENV} environment
# =============================================================================

project_name = "${PROJECT_NAME}"
environment  = "${ENV}"
aws_region   = "${AWS_REGION}"
github_repo  = "${GITHUB_ORG}/${GITHUB_REPO}"  # From bootstrap configuration

# ECR Repository (created by bootstrap)
ecr_repository_name = "${PROJECT_NAME}"  # Must match bootstrap configuration

# =============================================================================
# App Runner Configuration
# =============================================================================

# CPU and Memory
# CPU options: 256, 512, 1024, 2048, 4096 (in units, 1024 = 1 vCPU)
# Memory options: 512, 1024, 2048, 3072, 4096, 6144, 8192, 10240, 12288 (in MB)
apprunner_cpu    = "$([ "$ENV" = "prod" ] && echo "2048" || echo "1024")"
apprunner_memory = "$([ "$ENV" = "prod" ] && echo "4096" || echo "2048")"
apprunner_port   = 8000

# Auto Scaling
apprunner_min_instances  = $([ "$ENV" = "prod" ] && echo "2" || echo "1")
apprunner_max_instances  = $([ "$ENV" = "prod" ] && echo "25" || echo "10")
apprunner_max_concurrency = 100  # Max concurrent requests per instance

# Health Check
health_check_path                = "/health"
health_check_interval            = 10
health_check_timeout             = 5
health_check_healthy_threshold   = 1
health_check_unhealthy_threshold = 5

# =============================================================================
# API Gateway Configuration (Standard Mode)
# =============================================================================
# API Gateway is the standard entry point for cloud deployments
# For local development, set enable_direct_access = true

enable_api_gateway_standard = true   # Enable API Gateway as standard entry point
enable_direct_access        = false  # Disable direct App Runner URLs (cloud deployment)

# Rate Limiting
api_throttle_burst_limit = $([ "$ENV" = "prod" ] && echo "5000" || echo "1000")  # Burst limit
api_throttle_rate_limit  = $([ "$ENV" = "prod" ] && echo "10000" || echo "500")  # Requests per second

# Logging $([ "$ENV" = "prod" ] && echo "(standard for prod)" || echo "(verbose for ${ENV})")
api_log_retention_days = $([ "$ENV" = "prod" ] && echo "30" || echo "7")
api_logging_level      = "INFO"
enable_api_data_trace  = false  # Set to true for detailed request/response logging
enable_xray_tracing    = $([ "$ENV" = "prod" ] && echo "false" || echo "true")   # Enable X-Ray for debugging

# Caching $([ "$ENV" = "prod" ] && echo "(consider enabling for prod)" || echo "(disabled for ${ENV})")
enable_api_caching = false

# CORS $([ "$ENV" = "prod" ] && echo "(restrictive for prod)" || echo "(open for ${ENV})")
cors_allow_origins = $([ "$ENV" = "prod" ] && echo '["https://yourdomain.com"]' || echo '["*"]')
cors_allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
cors_allow_headers = ["Content-Type", "Authorization", "X-Requested-With"]

# API Key Authentication (Optional)
enable_api_key              = ${ENABLE_API_KEY}  # Set to true to enable API Key authentication
api_key_name                = ""     # Auto-generated if not specified
api_usage_plan_quota_limit  = 0      # Max requests per period (0 = unlimited)
api_usage_plan_quota_period = "MONTH" # DAY, WEEK, or MONTH

# Additional tags
additional_tags = {
  CostCenter = "engineering"
  Team       = "platform"
}
EOF
done

# =============================================================================
# Create README
# =============================================================================
echo "📝 Creating terraform/README.md..."
cat > "$TERRAFORM_DIR/README.md" <<EOF
# Application Infrastructure (App Runner)

This directory contains Terraform configuration for your App Runner application infrastructure.

## Structure

- \`main.tf\` - Main Terraform configuration and provider setup
- \`variables.tf\` - Variable definitions
- \`apprunner.tf\` - App Runner service resources
- \`api-gateway.tf\` - API Gateway configuration (optional)
- \`outputs.tf\` - Output values
- \`environments/\` - Environment-specific variable files
  - \`dev.tfvars\` - Development environment
  - \`test.tfvars\` - Test environment
  - \`prod.tfvars\` - Production environment
  - \`*-backend.hcl\` - Backend configurations (generated by \`make setup-terraform-backend\`)

## Prerequisites

1. Bootstrap infrastructure must be deployed first:
   \`\`\`bash
   make bootstrap-create
   make bootstrap-init
   make bootstrap-apply
   make setup-terraform-backend
   \`\`\`

2. Docker image must be built and pushed to ECR:
   \`\`\`bash
   make docker-build
   make docker-push-dev
   \`\`\`

## Usage

### Development Environment

\`\`\`bash
# Initialize Terraform
make app-init-dev

# Plan changes
make app-plan-dev

# Apply changes
make app-apply-dev

# View outputs
cd terraform && terraform output
\`\`\`

### Production Environment

\`\`\`bash
make app-init-prod
make app-plan-prod
make app-apply-prod
\`\`\`

## App Runner vs Lambda

This configuration uses **AWS App Runner** instead of Lambda:

| Feature | Lambda | App Runner |
|---------|--------|------------|
| **Runtime** | Event-driven, serverless functions | Containerized web applications |
| **Scaling** | Automatic, per request | Instance-based auto-scaling |
| **Cold Starts** | Yes (can be significant) | Minimal (instances stay warm) |
| **Pricing** | Pay per invocation + duration | Pay per hour per instance |
| **Best For** | Event processing, APIs | Long-running web services |
| **Configuration** | Memory (128MB-10GB) | CPU (0.25-4 vCPU) + Memory (0.5-12GB) |
| **Web Server** | Managed by AWS (Lambda URLs) | You provide (FastAPI, Flask, etc.) |

**When to use App Runner:**
- ✅ Long-running web applications
- ✅ WebSocket support needed
- ✅ Consistent traffic patterns
- ✅ Need control over web server configuration
- ✅ Want minimal cold starts

**When to use Lambda:**
- ✅ Event-driven workloads
- ✅ Sporadic traffic (pay only when used)
- ✅ Simple request/response APIs
- ✅ Need massive scale (thousands of concurrent requests)

## Customization

1. Edit \`environments/{env}.tfvars\` to customize settings per environment
2. Modify \`apprunner.tf\` to add more App Runner services
3. Enable API Gateway by setting \`enable_api_gateway_standard = true\` in tfvars
4. Add more resources as needed (databases, queues, etc.)

## API Gateway Integration

By default, API Gateway is enabled as the standard entry point:
- **API Gateway** → HTTP_PROXY → **App Runner Service**

Benefits:
- Custom domain names
- API Key authentication
- Rate limiting and throttling
- Request/response transformation
- Caching

To use direct App Runner URLs (development only):
\`\`\`hcl
enable_api_gateway_standard = false
enable_direct_access        = true
\`\`\`

## Notes

- App Runner services use container images from ECR
- CloudWatch Logs are automatically configured
- Health checks ensure service availability
- Auto-scaling based on concurrent requests per instance
- First apply will fail if Docker image doesn't exist in ECR
EOF

echo ""
echo "✅ App Runner Terraform configuration created successfully!"
echo ""
echo "📂 Created files:"
echo "   terraform/main.tf"
echo "   terraform/variables.tf"
echo "   terraform/apprunner.tf"
echo "   terraform/api-gateway.tf"
echo "   terraform/outputs.tf"
echo "   terraform/README.md"
for ENV in "${ENVIRONMENTS[@]}"; do
  echo "   terraform/environments/${ENV}.tfvars"
done
echo ""
echo "✅ App Runner Terraform configuration created successfully!"
echo ""
echo "=================================================="
echo "⚠️  IMPORTANT: Deploy via GitHub Actions Only"
echo "=================================================="
echo ""
echo "All AWS deployments MUST be done through GitHub Actions."
echo ""
echo "📋 Recommended deployment workflow:"
echo ""
echo "1. Review and customize the generated files:"
echo "   vim terraform/environments/dev.tfvars"
echo "   - Update github_repo with your actual repository"
echo "   - Adjust App Runner CPU/memory settings as needed"
echo "   - Configure auto-scaling parameters"
echo ""
echo "2. Ensure bootstrap infrastructure is deployed:"
echo "   make bootstrap-apply"
echo "   make setup-terraform-backend"
echo ""
echo "3. Configure GitHub repository secrets (from bootstrap output):"
echo "   make bootstrap-output  # Shows role ARNs, bucket names"
echo "   - Add AWS_ACCOUNT_ID and AWS_REGION to repository secrets"
echo "   - Add AWS_ROLE_ARN_DEV to dev environment secrets"
echo "   - Add AWS_ROLE_ARN_PROD to production environment secrets"
echo ""
echo "4. Deploy via GitHub Actions:"
echo "   git add ."
echo "   git commit -m 'feat: Add App Runner infrastructure'"
echo "   git push origin main"
echo ""
echo "   GitHub Actions will automatically:"
echo "   - Run tests"
echo "   - Build Docker image"
echo "   - Push to ECR"
echo "   - Deploy infrastructure with Terraform"
echo "   - Run smoke tests"
echo ""
echo "5. Monitor deployment:"
echo "   https://github.com/<YOUR-ORG>/<YOUR-REPO>/actions"
echo ""
echo "6. Deploy to production (when ready):"
echo "   git tag v1.0.0"
echo "   git push origin v1.0.0"
echo ""
echo "=================================================="
echo "💡 Why use App Runner?"
echo "=================================================="
echo "- ✅ Containerized web applications with full control"
echo "- ✅ Minimal cold starts (instances stay warm)"
echo "- ✅ WebSocket and long-running connection support"
echo "- ✅ Simple pricing (pay per instance hour)"
echo "- ✅ Automatic health checks and auto-scaling"
echo ""
echo "For more details, see: README.md#deploy-to-aws"
echo ""
