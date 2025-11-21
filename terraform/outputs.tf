# =============================================================================
# Application Infrastructure - Outputs
# =============================================================================

locals {
  api_gateway_enabled = var.enable_api_gateway_standard || var.enable_api_gateway
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.api.arn
}

output "lambda_function_url" {
  description = "Lambda Function URL endpoint (only when direct access is enabled)"
  value       = var.enable_direct_access ? aws_lambda_function_url.api[0].function_url : "Direct access disabled - use API Gateway"
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch Log Group name for Lambda"
  value       = aws_cloudwatch_log_group.lambda_api.name
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

output "cloudwatch_log_group_api_gateway" {
  description = "CloudWatch Log Group name for API Gateway"
  value       = local.api_gateway_enabled ? module.api_gateway_shared[0].cloudwatch_log_group_name : "Not enabled"
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
    var.enable_direct_access ? aws_lambda_function_url.api[0].function_url : "No endpoint configured"
  )
}
