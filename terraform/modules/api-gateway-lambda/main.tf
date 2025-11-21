# =============================================================================
# API Gateway Lambda Integration Module
# =============================================================================
# This module creates API Gateway resources and integration for Lambda functions
# using AWS_PROXY integration type
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
  api_key_required = var.api_key_required

  request_parameters = var.request_parameters
}

# Lambda AWS_PROXY integration
resource "aws_api_gateway_integration" "lambda" {
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
  statement_id  = var.permission_statement_id
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_execution_arn}/*/*"
}

# Root path method (optional, for /)
resource "aws_api_gateway_method" "root" {
  count = var.enable_root_method ? 1 : 0

  rest_api_id   = var.api_id
  resource_id   = var.api_root_resource_id
  http_method   = "ANY"
  authorization = var.authorization_type
  api_key_required = var.api_key_required
}

# Root path integration
resource "aws_api_gateway_integration" "root" {
  count = var.enable_root_method ? 1 : 0

  rest_api_id = var.api_id
  resource_id = var.api_root_resource_id
  http_method = aws_api_gateway_method.root[0].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn

  timeout_milliseconds = var.integration_timeout_milliseconds
}
