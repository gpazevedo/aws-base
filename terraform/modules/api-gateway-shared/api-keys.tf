# =============================================================================
# Per-Service API Keys Module
# =============================================================================
# Creates individual API keys for each service with separate usage plans
# Stores keys in AWS Secrets Manager for secure retrieval
# =============================================================================

# Create API Key for each service
resource "aws_api_gateway_api_key" "service_keys" {
  for_each = var.service_api_keys

  name        = "${var.project_name}-${var.environment}-${each.key}-key"
  description = each.value.description
  enabled     = true

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-${each.key}-key"
      Project     = var.project_name
      Environment = var.environment
      Service     = each.key
      Purpose     = "inter-service-communication"
    },
    var.tags
  )
}

# Create individual usage plan for each service (optional, for granular control)
resource "aws_api_gateway_usage_plan" "service_plans" {
  for_each = var.service_api_keys

  name        = "${var.project_name}-${var.environment}-${each.key}-plan"
  description = "Usage plan for ${each.key} service"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.api.stage_name
  }

  # Service-specific quota (if set)
  dynamic "quota_settings" {
    for_each = each.value.quota_limit > 0 ? [1] : []
    content {
      limit  = each.value.quota_limit
      period = each.value.quota_period
    }
  }

  # Use same throttle settings as main API Gateway
  throttle_settings {
    burst_limit = var.throttle_burst_limit
    rate_limit  = var.throttle_rate_limit
  }

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-${each.key}-plan"
      Project     = var.project_name
      Environment = var.environment
      Service     = each.key
    },
    var.tags
  )
}

# Associate each service API key with its usage plan
resource "aws_api_gateway_usage_plan_key" "service_plan_keys" {
  for_each = var.service_api_keys

  key_id        = aws_api_gateway_api_key.service_keys[each.key].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.service_plans[each.key].id
}

# =============================================================================
# Secrets Manager Integration
# =============================================================================
# Store each service's API key in AWS Secrets Manager for secure retrieval

resource "aws_secretsmanager_secret" "service_api_keys" {
  for_each = var.service_api_keys

  name        = "${var.project_name}/${var.environment}/${each.key}/api-key"
  description = "API Gateway key for ${each.key} service to call other services"

  tags = merge(
    {
      Name        = "${var.project_name}-${var.environment}-${each.key}-api-key-secret"
      Project     = var.project_name
      Environment = var.environment
      Service     = each.key
    },
    var.tags
  )
}

resource "aws_secretsmanager_secret_version" "service_api_keys" {
  for_each = var.service_api_keys

  secret_id     = aws_secretsmanager_secret.service_api_keys[each.key].id
  secret_string = aws_api_gateway_api_key.service_keys[each.key].value
}
