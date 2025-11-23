# =============================================================================
# API Gateway App Runner Integration Module - Outputs
# =============================================================================

output "service_name" {
  description = "Name of the integrated service"
  value       = var.service_name
}

output "base_resource_id" {
  description = "ID of the base resource (if using path prefix)"
  value       = local.use_path_prefix ? aws_api_gateway_resource.base[0].id : null
}

output "base_resource_path" {
  description = "Path of the base resource (if using path prefix)"
  value       = local.use_path_prefix ? aws_api_gateway_resource.base[0].path : null
}

output "proxy_resource_id" {
  description = "ID of the proxy resource"
  value       = aws_api_gateway_resource.proxy.id
}

output "proxy_resource_path" {
  description = "Path of the proxy resource"
  value       = aws_api_gateway_resource.proxy.path
}

output "integration_id" {
  description = "ID of the integration (for triggering redeployments)"
  value       = aws_api_gateway_integration.proxy.id
}

output "integration_uri" {
  description = "Integration URI"
  value       = aws_api_gateway_integration.proxy.uri
}
