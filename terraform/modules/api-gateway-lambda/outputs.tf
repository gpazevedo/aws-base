# =============================================================================
# API Gateway Lambda Integration Module - Outputs
# =============================================================================

output "proxy_resource_id" {
  description = "ID of the proxy resource"
  value       = aws_api_gateway_resource.proxy.id
}

output "proxy_resource_path" {
  description = "Path of the proxy resource"
  value       = aws_api_gateway_resource.proxy.path
}

output "proxy_method_http_method" {
  description = "HTTP method of the proxy method"
  value       = aws_api_gateway_method.proxy.http_method
}

output "lambda_permission_id" {
  description = "ID of the Lambda permission"
  value       = aws_lambda_permission.api_gateway.id
}
