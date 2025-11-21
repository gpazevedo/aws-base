# API Gateway Lambda Integration Module

This module creates API Gateway integration for Lambda functions using AWS_PROXY integration.

## Features

- Proxy resource configuration ({proxy+})
- ANY method support
- AWS_PROXY integration
- Lambda invoke permissions
- Root path support (optional)
- Configurable authorization

## Usage

```hcl
module "api_gateway_lambda" {
  source = "./modules/api-gateway-lambda"

  # API Gateway from shared module
  api_id                = module.api_gateway_shared.api_id
  api_root_resource_id  = module.api_gateway_shared.root_resource_id
  api_execution_arn     = module.api_gateway_shared.execution_arn

  # Lambda function
  lambda_function_name  = aws_lambda_function.api.function_name
  lambda_function_arn   = aws_lambda_function.api.arn
  lambda_invoke_arn     = aws_lambda_function.api.invoke_arn

  # Optional configuration
  path_part             = "{proxy+}"
  http_method           = "ANY"
  authorization_type    = "NONE"
  enable_root_method    = true
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| api_id | API Gateway REST API ID | string | required |
| api_root_resource_id | Root resource ID | string | required |
| api_execution_arn | Execution ARN | string | required |
| lambda_function_name | Lambda function name | string | required |
| lambda_function_arn | Lambda function ARN | string | required |
| lambda_invoke_arn | Lambda invoke ARN | string | required |
| path_part | Path part for proxy | string | {proxy+} |
| http_method | HTTP method | string | ANY |
| authorization_type | Authorization type | string | NONE |
| enable_root_method | Enable root path method | bool | true |

## Outputs

| Name | Description |
|------|-------------|
| proxy_resource_id | Proxy resource ID |
| proxy_resource_path | Proxy resource path |
| lambda_permission_id | Lambda permission ID |
