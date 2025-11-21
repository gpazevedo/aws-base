# API Gateway App Runner Integration Module

This module creates API Gateway integration for App Runner services using HTTP_PROXY integration.

## Features

- Proxy resource configuration ({proxy+})
- ANY method support
- HTTP_PROXY integration
- CORS support
- Root path support (optional)
- Configurable authorization
- VPC Link support (optional)

## Usage

```hcl
module "api_gateway_apprunner" {
  source = "./modules/api-gateway-apprunner"

  # API Gateway from shared module
  api_id                  = module.api_gateway_shared.api_id
  api_root_resource_id    = module.api_gateway_shared.root_resource_id

  # App Runner service
  apprunner_service_url   = aws_apprunner_service.api.service_url

  # Optional configuration
  path_part               = "{proxy+}"
  http_method             = "ANY"
  authorization_type      = "NONE"
  connection_type         = "INTERNET"
  enable_root_method      = true
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| api_id | API Gateway REST API ID | string | required |
| api_root_resource_id | Root resource ID | string | required |
| apprunner_service_url | App Runner service URL | string | required |
| path_part | Path part for proxy | string | {proxy+} |
| http_method | HTTP method | string | ANY |
| authorization_type | Authorization type | string | NONE |
| connection_type | Connection type (INTERNET/VPC_LINK) | string | INTERNET |
| enable_root_method | Enable root path method | bool | true |

## Outputs

| Name | Description |
|------|-------------|
| proxy_resource_id | Proxy resource ID |
| proxy_resource_path | Proxy resource path |
| integration_uri | Integration URI |

## Notes

- App Runner service URL should be provided without `https://` prefix
- VPC Link support requires additional VPC Link configuration
- CORS headers are automatically configured in method responses
