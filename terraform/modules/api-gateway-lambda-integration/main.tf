# =============================================================================
# API Gateway Lambda Integration Module
# =============================================================================
# This module creates API Gateway resources and integration for Lambda functions
# using AWS_PROXY integration type with path-based routing support
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

# Base resource for path prefix (e.g., /api, /worker)
# Only created when using path-based routing
resource "aws_api_gateway_resource" "base" {
  count = local.use_path_prefix ? 1 : 0

  rest_api_id = var.api_id
  parent_id   = var.api_root_resource_id
  path_part   = local.base_path_part
}

# Base path method (e.g., /api, /worker)
# Handles requests to the base path without trailing segments
resource "aws_api_gateway_method" "base" {
  count = local.use_path_prefix ? 1 : 0

  rest_api_id      = var.api_id
  resource_id      = aws_api_gateway_resource.base[0].id
  http_method      = var.http_method
  authorization    = var.authorization_type
  api_key_required = var.api_key_required

  request_parameters = var.request_parameters
}

# Base path integration
resource "aws_api_gateway_integration" "base" {
  count = local.use_path_prefix ? 1 : 0

  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.base[0].id
  http_method = aws_api_gateway_method.base[0].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn

  timeout_milliseconds = var.integration_timeout_milliseconds
}

# Proxy resource (e.g., /api/{proxy+}, /worker/{proxy+}, or /{proxy+})
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

  request_parameters = var.request_parameters
}

# Lambda AWS_PROXY integration for proxy
resource "aws_api_gateway_integration" "proxy" {
  rest_api_id = var.api_id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn

  timeout_milliseconds = var.integration_timeout_milliseconds
}

# Lambda permission to allow API Gateway to invoke the function
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "${var.permission_statement_id}-${var.service_name}"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
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

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn

  timeout_milliseconds = var.integration_timeout_milliseconds
}
