# =============================================================================
# API Gateway Shared Module - Outputs
# =============================================================================

output "api_id" {
  description = "ID of the REST API"
  value       = aws_api_gateway_rest_api.api.id
}

output "api_arn" {
  description = "ARN of the REST API"
  value       = aws_api_gateway_rest_api.api.arn
}

output "root_resource_id" {
  description = "Root resource ID of the REST API"
  value       = aws_api_gateway_rest_api.api.root_resource_id
}

output "execution_arn" {
  description = "Execution ARN of the REST API"
  value       = aws_api_gateway_rest_api.api.execution_arn
}

output "deployment_id" {
  description = "Deployment ID"
  value       = aws_api_gateway_deployment.api.id
}

output "stage_name" {
  description = "Stage name"
  value       = aws_api_gateway_stage.api.stage_name
}

output "stage_arn" {
  description = "Stage ARN"
  value       = aws_api_gateway_stage.api.arn
}

output "invoke_url" {
  description = "Invoke URL for the API Gateway stage"
  value       = aws_api_gateway_stage.api.invoke_url
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway.arn
}

# =============================================================================
# API Key Outputs
# =============================================================================

output "api_key_id" {
  description = "ID of the API Key (if enabled)"
  value       = var.enable_api_key ? aws_api_gateway_api_key.api_key[0].id : null
}

output "api_key_value" {
  description = "Value of the API Key (sensitive, if enabled)"
  value       = var.enable_api_key ? aws_api_gateway_api_key.api_key[0].value : null
  sensitive   = true
}

output "usage_plan_id" {
  description = "ID of the Usage Plan (if API Key is enabled)"
  value       = var.enable_api_key ? aws_api_gateway_usage_plan.usage_plan[0].id : null
}

# =============================================================================
# Per-Service API Key Outputs
# =============================================================================

output "service_api_key_ids" {
  description = "Map of service names to their API key IDs"
  value = {
    for service, key in aws_api_gateway_api_key.service_keys :
    service => key.id
  }
}

output "service_api_key_values" {
  description = "Map of service names to their API key values (sensitive)"
  value = {
    for service, key in aws_api_gateway_api_key.service_keys :
    service => key.value
  }
  sensitive = true
}

output "service_api_key_secrets" {
  description = "Map of service names to their Secrets Manager secret ARNs"
  value = {
    for service, secret in aws_secretsmanager_secret.service_api_keys :
    service => secret.arn
  }
}

output "service_usage_plan_ids" {
  description = "Map of service names to their usage plan IDs"
  value = {
    for service, plan in aws_api_gateway_usage_plan.service_plans :
    service => plan.id
  }
}
