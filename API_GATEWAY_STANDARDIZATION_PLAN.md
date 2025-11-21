# API Gateway Standardization - Implementation Plan

## Overview

This plan outlines the changes needed to make API Gateway the standard access point for all services (Lambda and App Runner), while maintaining the ability to use direct access for local development.

## Branch

`claude/api-gateway-standard-01PqDN99TX3Noq24Q9BEs3uR`

## Goals

1. **API Gateway as Standard Entry Point**: All cloud-deployed services accessible only via API Gateway
2. **No Direct Cloud URLs**: Disable Lambda Function URLs and App Runner direct access in cloud environments
3. **Local Development Support**: Allow direct access when running locally
4. **Shared Configuration**: Common API Gateway settings (security, throttling, CORS, logging)
5. **Service-Specific Integration**: Each service has its own integration module
6. **Modular Terraform**: Reusable modules for API Gateway configuration

---

## Architecture Changes

### Current Architecture
```
┌─────────────────────────────────────────────────┐
│ Lambda Function URL (Direct)                    │
│ https://xxx.lambda-url.region.on.aws/           │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ App Runner URL (Direct)                         │
│ https://xxx.region.awsapprunner.com             │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ API Gateway (Optional)                          │
│ https://xxx.execute-api.region.amazonaws.com    │
│   ↓                                              │
│   → Lambda or App Runner                        │
└─────────────────────────────────────────────────┘
```

### New Architecture
```
                    ┌────────────────────────────────────┐
                    │      API Gateway (Standard)        │
                    │  https://xxx.execute-api.....com   │
                    │                                    │
                    │  Features:                         │
                    │  - Rate Limiting/Throttling        │
                    │  - API Keys (optional)             │
                    │  - WAF Integration (optional)      │
                    │  - CORS Configuration              │
                    │  - CloudWatch Logging              │
                    │  - X-Ray Tracing (optional)        │
                    │  - Custom Domain (optional)        │
                    └────────────┬───────────────────────┘
                                 │
                    ┌────────────┴───────────┐
                    │                        │
           ┌────────▼──────┐        ┌───────▼────────┐
           │  Lambda       │        │  App Runner    │
           │  (No URL)     │        │  (Private)     │
           └───────────────┘        └────────────────┘

Local Development:
┌─────────────────────────────────────────────────┐
│ Direct Access Enabled                            │
│ (enable_direct_access = true)                   │
└─────────────────────────────────────────────────┘
```

---

## Terraform Module Structure

### New Directory Layout
```
terraform/
├── modules/
│   ├── api-gateway-shared/          # NEW: Shared API Gateway configuration
│   │   ├── main.tf                  # REST API, stage, deployment
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── waf.tf                   # Optional WAF rules
│   │   ├── throttling.tf            # Rate limiting, usage plans
│   │   ├── security.tf              # API keys, authorizers
│   │   └── README.md
│   │
│   ├── api-gateway-lambda/          # NEW: Lambda integration
│   │   ├── main.tf                  # AWS_PROXY integration
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   │
│   └── api-gateway-apprunner/       # NEW: App Runner integration
│       ├── main.tf                  # HTTP_PROXY integration
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
│
├── main.tf                           # MODIFIED: Use new modules
├── variables.tf                      # MODIFIED: Add API Gateway variables
├── api-gateway.tf                    # MODIFIED: Use modules instead of direct resources
├── lambda.tf                         # MODIFIED: Conditional Function URL
├── apprunner.tf                      # MODIFIED: Private service configuration
├── outputs.tf                        # MODIFIED: API Gateway as primary
└── environments/
    └── dev.tfvars                    # MODIFIED: New variables
```

---

## Required Changes

### 1. Bootstrap Changes (IAM Policies)

#### File: `bootstrap/main.tf`

Add new API Gateway management policy for GitHub Actions:

```hcl
resource "aws_iam_policy" "api_gateway_full" {
  count = var.enable_lambda || var.enable_apprunner ? 1 : 0

  name        = "${var.project_name}-api-gateway-full"
  description = "Full API Gateway management for ${var.project_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # REST API Management
      {
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:DELETE",
          "apigateway:PATCH"
        ]
        Resource = "arn:aws:apigateway:${var.aws_region}::/restapis/*"
      },
      # Account settings (for CloudWatch Logs role)
      {
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:PATCH"
        ]
        Resource = "arn:aws:apigateway:${var.aws_region}::/account"
      },
      # Usage Plans & API Keys
      {
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:DELETE"
        ]
        Resource = [
          "arn:aws:apigateway:${var.aws_region}::/usageplans/*",
          "arn:aws:apigateway:${var.aws_region}::/apikeys/*"
        ]
      },
      # VPC Links (for private integrations)
      {
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:DELETE"
        ]
        Resource = "arn:aws:apigateway:${var.aws_region}::/vpclinks/*"
      },
      # CloudWatch Logs for API Gateway
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:DeleteLogGroup"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/apigateway/${var.project_name}-*"
      },
      # IAM role for CloudWatch Logs (API Gateway account settings)
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PassRole",
          "iam:GetRole",
          "iam:DeleteRole",
          "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project_name}-apigateway-*"
      },
      # WAF (optional)
      {
        Effect = "Allow"
        Action = [
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}
```

#### Answer: **YES, bootstrap changes are needed** for comprehensive API Gateway management.

---

### 2. New Terraform Modules

#### Module: `api-gateway-shared`

**Purpose**: Common API Gateway configuration (REST API, stage, throttling, security, logging)

**Key Features**:
- REST API creation
- Deployment and stage management
- Rate limiting (burst and rate limits)
- API keys and usage plans (optional)
- CloudWatch logging and access logs
- X-Ray tracing (optional)
- CORS configuration
- WAF integration (optional)
- Custom domain (optional)

**Variables**:
```hcl
variable "project_name" {}
variable "environment" {}
variable "api_name" {}
variable "enable_rate_limiting" { default = true }
variable "throttle_burst_limit" { default = 5000 }
variable "throttle_rate_limit" { default = 10000 }
variable "enable_api_keys" { default = false }
variable "enable_waf" { default = false }
variable "enable_xray_tracing" { default = false }
variable "cors_allow_origins" { default = ["*"] }
variable "cors_allow_methods" { default = ["GET", "POST", "PUT", "DELETE", "OPTIONS"] }
variable "cors_allow_headers" { default = ["Content-Type", "Authorization"] }
variable "log_retention_days" { default = 7 }
```

---

#### Module: `api-gateway-lambda`

**Purpose**: Lambda-specific API Gateway integration (AWS_PROXY)

**Key Features**:
- Resource and method configuration
- Lambda integration (AWS_PROXY)
- Lambda invoke permissions
- Request/response mapping (if needed)

**Variables**:
```hcl
variable "api_id" {}               # From shared module
variable "api_root_resource_id" {}
variable "api_execution_arn" {}
variable "lambda_function_name" {}
variable "lambda_function_arn" {}
variable "lambda_invoke_arn" {}
variable "path_part" { default = "{proxy+}" }
variable "http_method" { default = "ANY" }
```

---

#### Module: `api-gateway-apprunner`

**Purpose**: App Runner-specific API Gateway integration (HTTP_PROXY)

**Key Features**:
- Resource and method configuration
- HTTP_PROXY integration to App Runner URL
- Request parameter mapping
- Health check configuration

**Variables**:
```hcl
variable "api_id" {}
variable "api_root_resource_id" {}
variable "apprunner_service_url" {}
variable "path_part" { default = "{proxy+}" }
variable "http_method" { default = "ANY" }
variable "connection_type" { default = "INTERNET" }
```

---

### 3. Variable Changes

#### File: `terraform/variables.tf`

**Add new variables**:
```hcl
# =============================================================================
# API Gateway Configuration (Standard)
# =============================================================================

variable "enable_api_gateway_standard" {
  description = "Enable API Gateway as standard entry point (recommended for production)"
  type        = bool
  default     = true
}

variable "enable_direct_access" {
  description = "Enable direct access URLs (Lambda Function URLs, App Runner direct). Set to true for local development."
  type        = bool
  default     = false
}

# Rate Limiting
variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit (requests)"
  type        = number
  default     = 5000
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 10000
}

# Security
variable "enable_api_keys" {
  description = "Enable API keys for API Gateway"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Enable AWS WAF for API Gateway"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for API Gateway"
  type        = bool
  default     = false
}

# CORS
variable "cors_allow_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_methods" {
  description = "CORS allowed HTTP methods"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "CORS allowed headers"
  type        = list(string)
  default     = ["Content-Type", "Authorization"]
}

# Logging
variable "api_log_retention_days" {
  description = "CloudWatch log retention for API Gateway logs"
  type        = number
  default     = 7
}
```

---

### 4. Lambda Changes

#### File: `terraform/lambda.tf`

**Modify Lambda Function URL creation**:
```hcl
# Lambda Function URL (conditional - only if direct access enabled)
resource "aws_lambda_function_url" "api" {
  count = var.enable_direct_access ? 1 : 0  # Changed from always creating

  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = true
    allow_origins     = var.cors_allow_origins
    allow_methods     = var.cors_allow_methods
    allow_headers     = var.cors_allow_headers
    max_age          = 86400
  }
}
```

---

### 5. App Runner Changes

#### File: `terraform/apprunner.tf`

**Consider private access** (optional - may require VPC connector):
```hcl
resource "aws_apprunner_service" "api" {
  count = var.enable_apprunner ? 1 : 0

  service_name = "${var.project_name}-${var.environment}-api"

  # ... existing configuration ...

  # Add network configuration for private access (optional)
  dynamic "network_configuration" {
    for_each = var.enable_api_gateway_standard && !var.enable_direct_access ? [1] : []
    content {
      ingress_configuration {
        is_publicly_accessible = false  # Make private if using API Gateway only
      }
    }
  }
}
```

**Note**: Making App Runner fully private requires a VPC connector and VPC Link in API Gateway, which adds complexity. **Recommendation**: Keep App Runner publicly accessible but document that API Gateway is the standard entry point.

---

### 6. API Gateway Module Usage

#### File: `terraform/api-gateway.tf`

**Replace existing resources with module calls**:
```hcl
# =============================================================================
# Shared API Gateway Configuration
# =============================================================================

module "api_gateway_shared" {
  source = "./modules/api-gateway-shared"
  count  = var.enable_api_gateway_standard ? 1 : 0

  project_name           = var.project_name
  environment            = var.environment
  api_name               = "${var.project_name}-${var.environment}-api"

  # Rate Limiting
  enable_rate_limiting   = true
  throttle_burst_limit   = var.api_throttle_burst_limit
  throttle_rate_limit    = var.api_throttle_rate_limit

  # Security
  enable_api_keys        = var.enable_api_keys
  enable_waf             = var.enable_waf
  enable_xray_tracing    = var.enable_xray_tracing

  # CORS
  cors_allow_origins     = var.cors_allow_origins
  cors_allow_methods     = var.cors_allow_methods
  cors_allow_headers     = var.cors_allow_headers

  # Logging
  log_retention_days     = var.api_log_retention_days
}

# =============================================================================
# Lambda Integration Module
# =============================================================================

module "api_gateway_lambda" {
  source = "./modules/api-gateway-lambda"
  count  = var.enable_api_gateway_standard && !var.enable_apprunner ? 1 : 0

  api_id                = module.api_gateway_shared[0].api_id
  api_root_resource_id  = module.api_gateway_shared[0].root_resource_id
  api_execution_arn     = module.api_gateway_shared[0].execution_arn

  lambda_function_name  = aws_lambda_function.api.function_name
  lambda_function_arn   = aws_lambda_function.api.arn
  lambda_invoke_arn     = aws_lambda_function.api.invoke_arn
}

# =============================================================================
# App Runner Integration Module
# =============================================================================

module "api_gateway_apprunner" {
  source = "./modules/api-gateway-apprunner"
  count  = var.enable_api_gateway_standard && var.enable_apprunner ? 1 : 0

  api_id                  = module.api_gateway_shared[0].api_id
  api_root_resource_id    = module.api_gateway_shared[0].root_resource_id
  apprunner_service_url   = aws_apprunner_service.api[0].service_url
}
```

---

### 7. Outputs Changes

#### File: `terraform/outputs.tf`

**Prioritize API Gateway URL**:
```hcl
output "primary_endpoint" {
  description = "Primary application endpoint (API Gateway in cloud, direct in local)"
  value = var.enable_api_gateway_standard ? module.api_gateway_shared[0].invoke_url : (
    var.enable_apprunner ? "https://${aws_apprunner_service.api[0].service_url}" :
    var.enable_direct_access ? aws_lambda_function_url.api[0].function_url : "Not configured"
  )
}

output "deployment_mode" {
  description = "Current deployment mode"
  value = var.enable_api_gateway_standard ? "api-gateway-standard" : "direct-access"
}
```

---

### 8. Environment Configuration

#### File: `terraform/environments/dev.tfvars`

**Add for development**:
```hcl
# API Gateway Configuration
enable_api_gateway_standard = true   # Use API Gateway
enable_direct_access        = false  # Disable direct URLs

# Rate limiting
api_throttle_burst_limit = 1000
api_throttle_rate_limit  = 500

# Security (dev - keep simple)
enable_api_keys     = false
enable_waf          = false
enable_xray_tracing = true  # Enable for debugging

# CORS (dev - open)
cors_allow_origins = ["*"]
```

#### File: `terraform/environments/local.tfvars` (NEW)

**Add for local development**:
```hcl
# Local Development Configuration
enable_api_gateway_standard = false  # Skip API Gateway
enable_direct_access        = true   # Enable direct access
```

---

## Bootstrap IAM Policy Changes

### Required: YES

**File**: `bootstrap/main.tf`

**Changes needed**:
1. Add comprehensive API Gateway management policy (shown above)
2. Add WAF permissions (optional)
3. Add X-Ray permissions (optional)
4. Add VPC Link permissions (if using private App Runner)

**Attach to roles**:
- `aws_iam_role.github_actions_dev`
- `aws_iam_role.github_actions_test`
- `aws_iam_role.github_actions_prod`

---

## Deploy Role Permissions Changes

### Required: YES

**Existing permissions** in `bootstrap/lambda.tf` are **insufficient**.

**Current** (lines 236-247):
```hcl
# API Gateway integration (if needed)
{
  Effect = "Allow"
  Action = [
    "apigateway:GET",
    "apigateway:POST",
    "apigateway:PUT",
    "apigateway:DELETE",
    "apigateway:PATCH"
  ]
  Resource = "arn:aws:apigateway:${var.aws_region}::/restapis/*"
}
```

**Needed additions**:
- Usage plans and API keys management
- VPC Links
- Account settings (for CloudWatch Logs role)
- WAF association
- CloudWatch Logs management
- IAM role management for API Gateway CloudWatch Logs

---

## Migration Strategy

### Phase 1: Module Creation (No Breaking Changes)
1. Create `modules/api-gateway-shared/`
2. Create `modules/api-gateway-lambda/`
3. Create `modules/api-gateway-apprunner/`
4. Add comprehensive documentation

### Phase 2: Bootstrap Updates
1. Add API Gateway management policy
2. Attach to GitHub Actions roles
3. Test with `terraform plan` in bootstrap

### Phase 3: Application Updates
1. Add new variables to `variables.tf`
2. Modify `api-gateway.tf` to use modules
3. Update `lambda.tf` to make Function URLs conditional
4. Update `outputs.tf` to prioritize API Gateway
5. Test with `terraform plan`

### Phase 4: Environment Configuration
1. Update `dev.tfvars`, `test.tfvars`, `prod.tfvars`
2. Create `local.tfvars` for local development
3. Document usage patterns

### Phase 5: Deployment
1. Deploy bootstrap changes first
2. Deploy application changes
3. Verify endpoints
4. Document rollback procedure

---

## Testing Strategy

### Local Development
```bash
# Use direct access for local testing
terraform apply -var="enable_api_gateway_standard=false" -var="enable_direct_access=true"
```

### Cloud Deployment (Dev)
```bash
# Use API Gateway standard
terraform apply -var-file="environments/dev.tfvars"
```

### Cloud Deployment (Prod)
```bash
# API Gateway with WAF and enhanced security
terraform apply -var-file="environments/prod.tfvars"
```

---

## Benefits

### Security
- ✅ Single entry point for all services
- ✅ Centralized rate limiting and throttling
- ✅ API key support (optional)
- ✅ WAF integration (optional)
- ✅ Standardized CORS policies

### Observability
- ✅ Centralized CloudWatch logging
- ✅ X-Ray tracing support
- ✅ Access logs with detailed request info
- ✅ CloudWatch metrics per API

### Cost Management
- ✅ Rate limiting prevents abuse
- ✅ Usage plans for cost control
- ✅ Consolidated logging (lower costs)

### Development Experience
- ✅ Local development mode with direct access
- ✅ Consistent URL structure across environments
- ✅ Easy to add custom domains
- ✅ Modular, reusable Terraform code

---

## Risks and Mitigations

### Risk 1: Breaking Existing Deployments
**Mitigation**: Use feature flags (`enable_api_gateway_standard`, `enable_direct_access`) to allow gradual migration

### Risk 2: Increased Latency
**Mitigation**: API Gateway adds ~10-30ms latency. Monitor and optimize if needed.

### Risk 3: Increased Costs
**Mitigation**: API Gateway REST API: $3.50 per million requests (first 333M). For most applications, the benefits outweigh costs.

### Risk 4: App Runner Private Access Complexity
**Mitigation**: Keep App Runner publicly accessible initially. API Gateway is the standard entry point, but direct URL still works (for debugging).

### Risk 5: Module Dependencies
**Mitigation**: Thorough testing of module outputs and inputs. Use `terraform plan` extensively before applying.

---

## Rollback Plan

If issues occur:

1. **Immediate**: Set `enable_api_gateway_standard = false` and `enable_direct_access = true`
2. **Apply**: `terraform apply` to restore direct access
3. **Investigate**: Review CloudWatch logs and errors
4. **Fix**: Address issues in modules
5. **Retry**: Re-enable API Gateway standard

---

## Timeline Estimate

- **Module Creation**: 2-3 hours
- **Bootstrap Updates**: 1 hour
- **Application Updates**: 2 hours
- **Testing**: 2-3 hours
- **Documentation**: 1 hour
- **Total**: ~8-10 hours

---

## Next Steps

1. ✅ Review and approve this plan
2. Create Terraform modules
3. Update bootstrap IAM policies
4. Update application Terraform files
5. Test in dev environment
6. Deploy to production
7. Update documentation

---

## Questions?

- **Do we need private App Runner?** No, recommend keeping it public but routing through API Gateway
- **What about custom domains?** Can be added to the shared module later
- **How to handle multiple services?** Each service gets its own module instance
- **What about WebSocket APIs?** This plan focuses on REST APIs. WebSocket would be a separate module.

---

**Status**: ✅ Plan Complete - Ready for Implementation
