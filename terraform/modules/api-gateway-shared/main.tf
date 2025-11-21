# =============================================================================
# API Gateway Shared Module
# =============================================================================
# This module creates the shared API Gateway REST API with common configuration
# including rate limiting, security, and logging
# =============================================================================

# REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = var.api_name
  description = "API Gateway for ${var.project_name} ${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    {
      Name        = var.api_name
      Project     = var.project_name
      Environment = var.environment
    },
    var.tags
  )
}

# Deployment
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Force new deployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode({
      rest_api_id = aws_api_gateway_rest_api.api.id
      timestamp   = timestamp()
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_rest_api.api
  ]
}

# Stage
resource "aws_api_gateway_stage" "api" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.environment

  # Enable X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing

  # Access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }

  tags = merge(
    {
      Name        = "${var.api_name}-${var.environment}"
      Project     = var.project_name
      Environment = var.environment
    },
    var.tags
  )
}

# CloudWatch Log Group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-api-gateway-logs"
      Project     = var.project_name
      Environment = var.environment
    },
    var.tags
  )
}

# Method settings for throttling
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api.stage_name
  method_path = "*/*"

  settings {
    # Throttling
    throttling_burst_limit = var.throttle_burst_limit
    throttling_rate_limit  = var.throttle_rate_limit

    # Logging
    logging_level      = var.api_logging_level
    data_trace_enabled = var.enable_data_trace
    metrics_enabled    = true

    # Caching (disabled by default)
    caching_enabled = var.enable_caching
  }
}
