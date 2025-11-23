# =============================================================================
# Application Infrastructure - Outputs
# =============================================================================
# NOTE: Service-specific outputs (Lambda functions, URLs, etc.) are defined
# in each lambda-{service}.tf file. This file contains only shared outputs.
# =============================================================================

# =============================================================================
# API Gateway Outputs (from shared module)
# =============================================================================

output "api_gateway_url" {
  description = "API Gateway endpoint URL (standard entry point)"
  value       = try(module.api_gateway_shared[0].invoke_url, "Not enabled")
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = try(module.api_gateway_shared[0].api_id, "Not enabled")
}

output "api_gateway_stage" {
  description = "API Gateway stage name"
  value       = try(module.api_gateway_shared[0].stage_name, "Not enabled")
}

output "api_key_id" {
  description = "API Key ID (if enabled)"
  value       = try(module.api_gateway_shared[0].api_key_id, "Not enabled")
}

output "api_key_value" {
  description = "API Key value (sensitive, if enabled)"
  value       = try(module.api_gateway_shared[0].api_key_value, null)
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
  description = "Primary application endpoint (API Gateway, if enabled)"
  value       = try(module.api_gateway_shared[0].invoke_url, "Not enabled - use service-specific Function URLs")
}

# =============================================================================
# Service-Specific Outputs
# =============================================================================
# Individual Lambda service outputs are defined in lambda-{service}.tf files:
# - lambda_{service}_function_name
# - lambda_{service}_function_arn
# - lambda_{service}_url
# - lambda_{service}_log_group
# =============================================================================
