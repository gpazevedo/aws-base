# =============================================================================
# API Gateway App Runner Integration Module
# =============================================================================
# This module creates API Gateway resources and integration for App Runner services
# using HTTP_PROXY integration type
# =============================================================================

# Proxy resource
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = var.api_id
  parent_id   = var.api_root_resource_id
  path_part   = var.path_part
}

# ANY method for proxy resource
resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = var.api_id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = var.http_method
  authorization = var.authorization_type

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# App Runner HTTP_PROXY integration
resource "aws_api_gateway_integration" "apprunner" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "https://${var.apprunner_service_url}/{proxy}"
  connection_type         = var.connection_type

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  timeout_milliseconds = var.integration_timeout_milliseconds
}

# Method response
resource "aws_api_gateway_method_response" "proxy" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Root path method (optional, for /)
resource "aws_api_gateway_method" "root" {
  count = var.enable_root_method ? 1 : 0

  rest_api_id   = var.api_id
  resource_id   = var.api_root_resource_id
  http_method   = "ANY"
  authorization = var.authorization_type
}

# Root path integration
resource "aws_api_gateway_integration" "root" {
  count = var.enable_root_method ? 1 : 0

  rest_api_id = var.api_id
  resource_id = var.api_root_resource_id
  http_method = aws_api_gateway_method.root[0].http_method

  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "https://${var.apprunner_service_url}"
  connection_type         = var.connection_type

  timeout_milliseconds = var.integration_timeout_milliseconds
}

# Root method response
resource "aws_api_gateway_method_response" "root" {
  count = var.enable_root_method ? 1 : 0

  rest_api_id = var.api_id
  resource_id = var.api_root_resource_id
  http_method = aws_api_gateway_method.root[0].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}
