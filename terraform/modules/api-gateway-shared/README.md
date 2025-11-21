# API Gateway Shared Module

This module creates a shared API Gateway REST API with common configuration including rate limiting, logging, and monitoring.

## Features

- REST API creation
- Deployment and stage management
- Rate limiting and throttling
- CloudWatch logging and access logs
- X-Ray tracing support (optional)
- API caching (optional)
- Configurable log retention

## Usage

```hcl
module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"

  project_name = "my-project"
  environment  = "dev"
  api_name     = "my-project-dev-api"

  # Rate limiting
  throttle_burst_limit = 5000
  throttle_rate_limit  = 10000

  # Logging
  log_retention_days = 7
  api_logging_level  = "INFO"

  # Monitoring
  enable_xray_tracing = true

  tags = {
    Team = "platform"
  }
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| project_name | Project name | string | required |
| environment | Environment name | string | required |
| api_name | API Gateway REST API name | string | required |
| throttle_burst_limit | Throttle burst limit | number | 5000 |
| throttle_rate_limit | Throttle rate limit (req/sec) | number | 10000 |
| log_retention_days | Log retention days | number | 7 |
| api_logging_level | Logging level (OFF/ERROR/INFO) | string | INFO |
| enable_xray_tracing | Enable X-Ray tracing | bool | false |
| enable_caching | Enable API caching | bool | false |

## Outputs

| Name | Description |
|------|-------------|
| api_id | REST API ID |
| root_resource_id | Root resource ID |
| execution_arn | Execution ARN |
| invoke_url | API invoke URL |
| cloudwatch_log_group_name | CloudWatch log group name |
