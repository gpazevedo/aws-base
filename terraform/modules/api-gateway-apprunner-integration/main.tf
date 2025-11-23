# =============================================================================
# API Gateway App Runner Integration Module
# =============================================================================
# This module creates API Gateway resources and integration for App Runner services
# using HTTP_PROXY integration type with path-based routing support
# =============================================================================

locals {
  # Determine if we're using path-based routing or root
  use_path_prefix = var.path_prefix != ""

  # Compute actual path parts
  base_path_part  = local.use_path_prefix ? var.path_prefix : var.path_part
  proxy_path_part = local.use_path_prefix ? "{proxy+}" : var.path_part

  # For path-based routing: /prefix and /prefix/{proxy+}
  # For root routing: / and /{proxy+}
  parent_resource_id = local.use_path_prefix ? aws_api_gateway_resource.base[0].id : var.api_root_resource_id
}

# Base resource for path prefix (e.g., /web, /admin)
# Only created when using path-based routing
resource "aws_api_gateway_resource" "base" {
  count = local.use_path_prefix ? 1 : 0

  rest_api_id = var.api_id
  parent_id   = var.api_root_resource_id
  path_part   = local.base_path_part
}

# Base path method (e.g., /web, /admin)
# Handles requests to the base path without trailing segments
resource "aws_api_gateway_method" "base" {
  count = local.use_path_prefix ? 1 : 0

  rest_api_id      = var.api_id
  resource_id      = aws_api_gateway_resource.base[0].id
  http_method      = var.http_method
  authorization    = var.authorization_type
  api_key_required = var.api_key_required
}

# Base path integration
resource "aws_api_gateway_integration" "base" {
  count = local.use_path_prefix ? 1 : 0

  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.base[0].id
  http_method = aws_api_gateway_method.base[0].http_method

  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "https://${var.apprunner_service_url}"
  connection_type         = var.connection_type

  timeout_milliseconds = var.integration_timeout_milliseconds
}

# Base method response
resource "aws_api_gateway_method_response" "base" {
  count = local.use_path_prefix ? 1 : 0

  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.base[0].id
  http_method = aws_api_gateway_method.base[0].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Proxy resource (e.g., /web/{proxy+}, /admin/{proxy+}, or /{proxy+})
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = var.api_id
  parent_id   = local.parent_resource_id
  path_part   = local.proxy_path_part
}

# ANY method for proxy resource
resource "aws_api_gateway_method" "proxy" {
  rest_api_id      = var.api_id
  resource_id      = aws_api_gateway_resource.proxy.id
  http_method      = var.http_method
  authorization    = var.authorization_type
  api_key_required = var.api_key_required

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# App Runner HTTP_PROXY integration for proxy
resource "aws_api_gateway_integration" "proxy" {
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

# Proxy method response
resource "aws_api_gateway_method_response" "proxy" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Root path method (only when enable_root_method is true AND no path_prefix)
# This allows one service to handle the root / path
resource "aws_api_gateway_method" "root" {
  count = var.enable_root_method && !local.use_path_prefix ? 1 : 0

  rest_api_id      = var.api_id
  resource_id      = var.api_root_resource_id
  http_method      = "ANY"
  authorization    = var.authorization_type
  api_key_required = var.api_key_required
}

# Root path integration
resource "aws_api_gateway_integration" "root" {
  count = var.enable_root_method && !local.use_path_prefix ? 1 : 0

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
  count = var.enable_root_method && !local.use_path_prefix ? 1 : 0

  rest_api_id = var.api_id
  resource_id = var.api_root_resource_id
  http_method = aws_api_gateway_method.root[0].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}
