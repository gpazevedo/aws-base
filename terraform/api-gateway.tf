# =============================================================================
# API Gateway Configuration (Standard Mode)
# =============================================================================
# This file configures API Gateway as the standard entry point for services
# Uses modular architecture for shared configuration and service-specific integrations
# =============================================================================

locals {
  # Determine if API Gateway should be enabled (standard mode or legacy enable_api_gateway)
  api_gateway_enabled = var.enable_api_gateway_standard || var.enable_api_gateway
}

# =============================================================================
# Shared API Gateway Module
# =============================================================================
# Creates REST API, stage, deployment, logging, and rate limiting

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

  # Pass integration IDs to trigger redeployment when integrations change
  # This creates an implicit dependency on the integration modules
  integration_ids = compact([
    try(module.api_gateway_lambda_api[0].integration_id, ""),
    try(module.api_gateway_apprunner_apprunner[0].integration_id, "")
  ])
}

# =============================================================================
# Lambda Service Integrations
# =============================================================================
# Each Lambda service gets its own integration module instance
# Services are added by setup-terraform-lambda.sh script
#
# Path-based routing: Each service gets /service-name/* paths
# Root routing: One service can handle /* (set path_prefix = "")
#
# =============================================================================

# Integration for 'api' Lambda service
module "api_gateway_lambda_api" {
  source = "./modules/api-gateway-lambda-integration"
  count  = local.api_gateway_enabled ? 1 : 0

  # Service configuration
  service_name = "api"
  path_prefix  = ""  # Empty = root path (handles / and /*)

  # API Gateway from shared module
  api_id                = module.api_gateway_shared[0].api_id
  api_root_resource_id  = module.api_gateway_shared[0].root_resource_id
  api_execution_arn     = module.api_gateway_shared[0].execution_arn

  # Lambda function
  lambda_function_name  = aws_lambda_function.api.function_name
  lambda_invoke_arn     = aws_lambda_function.api.invoke_arn

  # Configuration
  enable_root_method    = true  # Allow this service to handle /
  api_key_required      = var.enable_api_key
}

# =============================================================================
# Additional Lambda services will be appended here by setup scripts
# Example:
# module "api_gateway_lambda_worker" {
#   source = "./modules/api-gateway-lambda-integration"
#   count  = local.api_gateway_enabled ? 1 : 0
#
#   service_name         = "worker"
#   path_prefix          = "worker"  # Routes /worker/* to worker service
#   api_id               = module.api_gateway_shared[0].api_id
#   api_root_resource_id = module.api_gateway_shared[0].root_resource_id
#   api_execution_arn    = module.api_gateway_shared[0].execution_arn
#   lambda_function_name = aws_lambda_function.worker.function_name
#   lambda_invoke_arn    = aws_lambda_function.worker.invoke_arn
#   enable_root_method   = false
#   api_key_required     = var.enable_api_key
# }
# =============================================================================

# Integration for 'apprunner' AppRunner service
module "api_gateway_apprunner_apprunner" {
  source = "./modules/api-gateway-apprunner-integration"
  count  = local.api_gateway_enabled ? 1 : 0

  service_name          = "apprunner"
  path_prefix           = "apprunner"  # /apprunner, /apprunner/*

  api_id                = module.api_gateway_shared[0].api_id
  api_root_resource_id  = module.api_gateway_shared[0].root_resource_id
  api_execution_arn     = module.api_gateway_shared[0].execution_arn

  apprunner_service_url = aws_apprunner_service.apprunner.service_url

  enable_root_method    = false
  api_key_required      = var.enable_api_key
}
