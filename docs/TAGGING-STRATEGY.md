# AWS Resource Tagging Strategy

## Overview

This document describes the standardized tagging strategy for all AWS resources in this project. Proper tagging enables cost allocation, resource organization, automation, and compliance.

## Tag Categories

### 1. Automatically Applied Tags (Provider Default Tags)

These tags are automatically applied to **ALL** AWS resources through the Terraform AWS provider's `default_tags` configuration.

| Tag | Description | Example | Source |
|-----|-------------|---------|--------|
| `Project` | Project name | `fingus` | `var.project_name` |
| `Environment` | Environment name | `dev`, `test`, `prod` | `var.environment` |
| `CostCenter` | Cost center for billing | `engineering`, `operations` | `var.cost_center` |
| `Team` | Responsible team | `platform`, `backend`, `frontend` | `var.team` |
| `ManagedBy` | Infrastructure management tool | `Terraform` | Static value |
| `Repository` | Source code repository | `gpazevedo/figus` | `var.github_repo` |

**Configuration Location:** [terraform/main.tf](../terraform/main.tf)

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      CostCenter  = var.cost_center
      Team        = var.team
      ManagedBy   = "Terraform"
      Repository  = var.github_repo
    }
  }
}
```

### 2. Resource-Specific Tags

These tags are applied individually to specific resources to provide additional context.

| Tag | Description | Example | Applied To |
|-----|-------------|---------|------------|
| `Name` | Human-readable resource name | `fingus-dev-api` | All resources |
| `Service` | Service identifier | `api`, `runner`, `worker` | Lambda, AppRunner services |
| `Description` | Resource description | `api Lambda function` | Optional, where relevant |

## Tag Implementation

### Lambda Functions

**Location:** [terraform/lambda-{service}.tf](../terraform/lambda-api.tf)

```hcl
resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-${var.environment}-api"
  # ... other configuration ...

  tags = {
    Name        = "${var.project_name}-${var.environment}-api"
    Service     = "api"
    Description = "api Lambda function"
  }
  # Note: Project, Environment, CostCenter, Team, ManagedBy, Repository
  # are automatically applied via provider default_tags
}
```

### AppRunner Services

**Location:** [terraform/apprunner-{service}.tf](../terraform/apprunner-runner.tf)

```hcl
resource "aws_apprunner_service" "runner" {
  service_name = "${var.project_name}-${var.environment}-runner"
  # ... other configuration ...

  tags = {
    Name        = "${var.project_name}-${var.environment}-runner"
    Service     = "runner"
    Description = "runner App Runner service"
  }
  # Note: Project, Environment, CostCenter, Team, ManagedBy, Repository
  # are automatically applied via provider default_tags
}
```

### CloudWatch Log Groups

```hcl
resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-api"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name    = "${var.project_name}-${var.environment}-api-logs"
    Service = "api"
  }
}
```

### API Gateway Resources

API Gateway resources use the modular tagging approach with common tags passed through variables.

**Location:** [terraform/modules/api-gateway-shared/main.tf](../terraform/modules/api-gateway-shared/main.tf)

```hcl
resource "aws_api_gateway_rest_api" "api" {
  name        = var.api_name
  description = "API Gateway for ${var.project_name} ${var.environment}"

  tags = merge(
    {
      Name        = var.api_name
      Project     = var.project_name
      Environment = var.environment
    },
    var.tags
  )
}
```

## Configuration

### Variables

**Location:** [terraform/variables.tf](../terraform/variables.tf)

```hcl
variable "cost_center" {
  description = "Cost center for resource tagging and cost allocation"
  type        = string
  default     = "engineering"
}

variable "team" {
  description = "Team responsible for the resources"
  type        = string
  default     = "platform"
}
```

### Environment Configuration

Set tag values in environment-specific variable files:

**Location:** [terraform/environments/{env}.tfvars](../terraform/environments/)

```hcl
# =============================================================================
# Resource Tagging
# =============================================================================

cost_center = "engineering"
team        = "platform"

# Additional tags (optional)
additional_tags = {}
```

## Complete Tag Example

When a Lambda function is created, it will have the following tags:

```hcl
# From provider default_tags (automatic):
Project     = "fingus"
Environment = "dev"
CostCenter  = "engineering"
Team        = "platform"
ManagedBy   = "Terraform"
Repository  = "gpazevedo/figus"

# From resource tags (explicit):
Name        = "fingus-dev-api"
Service     = "api"
Description = "api Lambda function"
```

## Use Cases

### Cost Allocation

Use tags to track costs by:
- **Environment**: `Environment=prod`, `Environment=dev`
- **Team**: `Team=platform`, `Team=backend`
- **Cost Center**: `CostCenter=engineering`, `CostCenter=operations`
- **Service**: `Service=api`, `Service=runner`

**AWS Cost Explorer Filter:**
```
Tag: Environment = prod
Tag: CostCenter = engineering
Tag: Service = api
```

### Resource Organization

Find all resources for a specific service:
```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Service,Values=api" \
  --region us-east-1
```

Find all resources in dev environment:
```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Environment,Values=dev" \
  --region us-east-1
```

### Automation

Use tags for automated operations:
- Start/stop non-production resources: `Environment != prod`
- Apply backup policies: `Environment = prod`
- Security scanning: `ManagedBy = Terraform`

## Best Practices

### 1. Consistency

- Always use the same tag keys across all resources
- Use consistent casing (PascalCase for tag keys)
- Use lowercase for tag values (except where required)

### 2. Required vs Optional

**Required tags (via default_tags):**
- `Project`, `Environment`, `CostCenter`, `Team`, `ManagedBy`, `Repository`

**Recommended tags:**
- `Name`, `Service` (for service resources)

**Optional tags:**
- `Description`, any additional tags in `additional_tags`

### 3. Naming Conventions

**Tag Values:**
- Environment: `dev`, `test`, `prod` (lowercase)
- Service: Match directory name in `backend/` (e.g., `api`, `runner`, `worker`)
- Name: `${project}-${environment}-${service}` (e.g., `fingus-dev-api`)

### 4. Tag Management

- **Terraform-managed resources**: Tags are managed via Terraform (DO NOT manually modify)
- **Manual resources**: Apply minimum required tags manually
- **Cost allocation**: Enable cost allocation tags in AWS Billing Console

## Customization

### Per-Environment Customization

Customize tags for specific environments:

```hcl
# terraform/environments/prod.tfvars
cost_center = "operations"  # Different cost center for prod
team        = "production-support"

# terraform/environments/dev.tfvars
cost_center = "engineering"
team        = "platform"
```

### Additional Tags

Add custom tags using `additional_tags`:

```hcl
# terraform/environments/prod.tfvars
additional_tags = {
  Compliance   = "SOC2"
  DataClass    = "sensitive"
  BackupPolicy = "daily"
}
```

## Bootstrap Infrastructure

The bootstrap infrastructure (S3, IAM, ECR, etc.) uses a similar tagging strategy.

**Location:** [bootstrap/main.tf](../bootstrap/main.tf)

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project       = var.project_name
        ManagedBy     = "terraform-bootstrap"
        Purpose       = "cicd-infrastructure"
        Terraform     = "true"
        PythonVersion = var.python_version
      },
      var.additional_tags
    )
  }
}
```

## Verification

### Check Tags on Resources

**Lambda Function:**
```bash
aws lambda get-function --function-name fingus-dev-api \
  --query 'Tags' --output json
```

**AppRunner Service:**
```bash
aws apprunner list-tags-for-resource \
  --resource-arn <service-arn>
```

**All Resources with Tag:**
```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Project,Values=fingus" \
  --region us-east-1
```

### Cost Allocation Tags

1. Go to AWS Billing Console
2. Navigate to Cost Allocation Tags
3. Activate tags:
   - `Project`
   - `Environment`
   - `CostCenter`
   - `Team`
   - `Service`

## Troubleshooting

### Tags Not Appearing

**Issue:** Tags not showing on resources

**Solutions:**
1. Check provider `default_tags` configuration in [terraform/main.tf](../terraform/main.tf)
2. Verify variables are set in environment tfvars files
3. Run `terraform plan` to see planned tag changes
4. For existing resources, run `terraform apply` to update tags

### Inconsistent Tags

**Issue:** Different resources have different tag sets

**Solution:**
1. Use provider `default_tags` for common tags (preferred)
2. Avoid manually setting common tags on individual resources
3. Only set resource-specific tags (`Name`, `Service`) on resources

### Cost Allocation Not Working

**Issue:** Tags not appearing in AWS Cost Explorer

**Solution:**
1. Activate cost allocation tags in AWS Billing Console
2. Wait 24 hours for tags to appear in Cost Explorer
3. Ensure tags are applied to resources (not just in Terraform code)

## Migration Guide

### Adding Tags to Existing Resources

If you're adding tags to existing infrastructure:

1. **Update variable files:**
   ```hcl
   cost_center = "engineering"
   team        = "platform"
   ```

2. **Run Terraform plan:**
   ```bash
   cd terraform
   terraform plan -var-file=environments/dev.tfvars
   ```

3. **Review tag changes:**
   - Verify only tags are being updated
   - No resources should be recreated

4. **Apply changes:**
   ```bash
   terraform apply -var-file=environments/dev.tfvars
   ```

## References

- [AWS Tagging Best Practices](https://docs.aws.amazon.com/whitepapers/latest/tagging-best-practices/tagging-best-practices.html)
- [Terraform AWS Provider Default Tags](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags)
- [AWS Cost Allocation Tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html)
- [Terraform Variables Documentation](../terraform/variables.tf)
- [Environment Configuration](../terraform/environments/)

---

**Last Updated:** 2025-11-25
**Related Documentation:**
- [Terraform Bootstrap Guide](TERRAFORM-BOOTSTRAP.md)
- [AWS Services Integration](AWS-SERVICES-INTEGRATION.md)
- [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md)
