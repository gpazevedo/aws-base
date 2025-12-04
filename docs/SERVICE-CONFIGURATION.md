# Service Configuration Pattern

This document explains how to configure Lambda and App Runner services in this project using the self-contained, local configuration pattern.

## Overview

Each service's configuration lives in its own Terraform file using `locals` blocks, making services self-contained and easier to manage. Configuration is **not** centralized in `tfvars` files.

## Configuration Location

### Lambda Services

Configuration is in `terraform/lambda-{service}.tf`:

- `terraform/lambda-api.tf` - API service configuration
- `terraform/lambda-s3vector.tf` - S3 Vector service configuration

### App Runner Services

Configuration is in `terraform/apprunner-{service}.tf`:

- `terraform/apprunner-runner.tf` - Runner service configuration

## Lambda Configuration Pattern

### Example: lambda-s3vector.tf

```hcl
# Service-specific configuration
# Edit these values to customize this Lambda function
locals {
  s3vector_config = {
    memory_size = 1024
    timeout     = 60
    # Bedrock configuration
    bedrock_model_id   = "amazon.titan-embed-text-v2:0"
    # S3 Vector storage
    vector_bucket_name = "${var.project_name}-${var.environment}-vector-embeddings"
  }
}

# Lambda function using container image
resource "aws_lambda_function" "s3vector" {
  function_name = "${var.project_name}-${var.environment}-s3vector"
  role          = data.aws_iam_role.lambda_execution_s3vector.arn

  # Resource configuration - uses local config
  memory_size   = local.s3vector_config.memory_size
  timeout       = local.s3vector_config.timeout
  architectures = [var.lambda_architecture]

  # Environment variables
  environment {
    variables = {
      ENVIRONMENT        = var.environment
      PROJECT_NAME       = var.project_name
      SERVICE_NAME       = "s3vector"
      LOG_LEVEL          = var.environment == "prod" ? "INFO" : "DEBUG"
      BEDROCK_MODEL_ID   = local.s3vector_config.bedrock_model_id
      VECTOR_BUCKET_NAME = local.s3vector_config.vector_bucket_name
    }
  }
}
```

### Lambda Configuration Options

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `memory_size` | number | Memory allocation in MB | `1024` |
| `timeout` | number | Timeout in seconds | `60` |
| Custom fields | any | Service-specific configs | `bedrock_model_id` |

**Note**: Custom fields can be added to the `locals` block and referenced in environment variables.

## App Runner Configuration Pattern

### Example: apprunner-runner.tf

```hcl
# Service-specific configuration
# Edit these values to customize this App Runner service
locals {
  runner_config = {
    cpu               = "1024"
    memory            = "2048"
    port              = 8080
    min_instances     = 1
    max_instances     = 5
    max_concurrency   = 100
    health_check_path = "/health"
    # Add service-specific environment variables here
    environment_variables = {
      # KEY = "value"
    }
  }
}

# App Runner Service
resource "aws_apprunner_service" "runner" {
  service_name = "${var.project_name}-${var.environment}-runner"

  source_configuration {
    image_repository {
      image_configuration {
        # Port - uses local config
        port = local.runner_config.port

        runtime_environment_variables = merge(
          {
            ENVIRONMENT  = var.environment
            PROJECT_NAME = var.project_name
            SERVICE_NAME = "runner"
            LOG_LEVEL    = var.environment == "prod" ? "INFO" : "DEBUG"
          },
          local.runner_config.environment_variables
        )
      }
    }
  }

  instance_configuration {
    # CPU and Memory - uses local config
    cpu    = local.runner_config.cpu
    memory = local.runner_config.memory
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = local.runner_config.health_check_path
  }
}

# Auto Scaling Configuration
resource "aws_apprunner_auto_scaling_configuration_version" "runner" {
  auto_scaling_configuration_name = "${var.project_name}-${var.environment}-runner-as"

  # Uses local config
  min_size        = local.runner_config.min_instances
  max_size        = local.runner_config.max_instances
  max_concurrency = local.runner_config.max_concurrency
}
```

### App Runner Configuration Options

| Field | Type | Description | Valid Values |
|-------|------|-------------|--------------|
| `cpu` | string | CPU units | "256", "512", "1024", "2048", "4096" |
| `memory` | string | Memory in MB | "512", "1024", "2048", "3072", "4096", "6144", "8192", "10240", "12288" |
| `port` | number | Container port | `8080` |
| `min_instances` | number | Min containers | `1` |
| `max_instances` | number | Max containers | `5` |
| `max_concurrency` | number | Requests per container | `100` |
| `health_check_path` | string | Health check endpoint | `"/health"` |
| `environment_variables` | map(string) | Custom env vars | `{ KEY = "value" }` |

## Adding Service-Specific Configuration

### Lambda Example

To add custom configuration to a Lambda service:

1. Edit `terraform/lambda-{service}.tf`

2. Add fields to the `locals` block:

```hcl
locals {
  myservice_config = {
    memory_size = 512
    timeout     = 30
    # Custom configuration
    database_url = "postgresql://..."
    api_key      = "secret-key"
  }
}
```

3. Reference in environment variables:

```hcl
environment {
  variables = {
    ENVIRONMENT  = var.environment
    DATABASE_URL = local.myservice_config.database_url
    API_KEY      = local.myservice_config.api_key
  }
}
```

### App Runner Example

To add custom environment variables to an App Runner service:

1. Edit `terraform/apprunner-{service}.tf`

2. Add to `environment_variables` map:

```hcl
locals {
  runner_config = {
    cpu    = "1024"
    memory = "2048"
    # ... other fields ...
    environment_variables = {
      DATABASE_URL = "postgresql://..."
      REDIS_URL    = "redis://..."
      API_KEY      = "secret-key"
    }
  }
}
```

3. These are automatically merged with standard variables via `merge()`.

## Setup Script Behavior

When you run `/add-service` or use the setup scripts directly:

- `./scripts/setup-terraform-lambda.sh {service}` - Generates Lambda Terraform with `locals` block
- `./scripts/setup-terraform-apprunner.sh {service}` - Generates App Runner Terraform with `locals` block

Both scripts create files with sensible defaults that you can customize.

## Migration from Centralized Config

If you have old services using `var.lambda_service_configs` or `var.apprunner_service_configs`:

### Before (Centralized)

```hcl
# In terraform/environments/dev.tfvars
lambda_service_configs = {
  myservice = {
    memory_size = 1024
    timeout     = 60
  }
}

# In terraform/lambda-myservice.tf
memory_size = try(var.lambda_service_configs["myservice"].memory_size, var.lambda_memory_size)
```

### After (Local)

```hcl
# In terraform/lambda-myservice.tf
locals {
  myservice_config = {
    memory_size = 1024
    timeout     = 60
  }
}

resource "aws_lambda_function" "myservice" {
  memory_size = local.myservice_config.memory_size
  timeout     = local.myservice_config.timeout
}
```

## Benefits of Local Configuration

1. **Self-Contained**: Each service file has everything you need
2. **Easier to Navigate**: No hunting through large tfvars files
3. **Better Version Control**: Service changes are isolated to service files
4. **Clearer Ownership**: Service config lives with service definition
5. **Scalability**: Adding services doesn't bloat central configs
6. **Type Safety**: No relying on optional fields with `try()`

## Environment-Specific Configuration

For environment-specific values, use ternary operators:

```hcl
locals {
  myservice_config = {
    memory_size = var.environment == "prod" ? 2048 : 1024
    timeout     = var.environment == "prod" ? 300 : 60
    min_instances = var.environment == "prod" ? 2 : 1
  }
}
```

## Best Practices

1. **Keep it Simple**: Only add configuration you actually need
2. **Use Comments**: Document what each field does
3. **Set Sensible Defaults**: Start with conservative values
4. **Environment Awareness**: Use `var.environment` for prod/dev differences
5. **Validate Values**: Use appropriate data types and AWS valid values
6. **Secret Management**: Never put secrets in Terraform - use AWS Secrets Manager or Parameter Store

## Troubleshooting

### Issue: Terraform shows pending changes

If Terraform shows changes after switching from centralized to local config:

1. Make sure all `try()` references are removed
2. Ensure `locals` values match previous centralized values
3. Run `terraform plan` to review differences

### Issue: Service config not applied

1. Check that you're referencing `local.{service}_config.field` correctly
2. Verify the `locals` block is before the resource that uses it
3. Confirm no typos in field names

## See Also

- [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md) - Path-based routing guide
- [Terraform Bootstrap Guide](TERRAFORM-BOOTSTRAP.md) - Infrastructure setup
- [API Endpoints](API-ENDPOINTS.md) - API documentation
