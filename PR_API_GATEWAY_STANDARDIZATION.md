# Pull Request: API Gateway Standardization Plan

**Branch**: `claude/api-gateway-standard-01PqDN99TX3Noq24Q9BEs3uR`
**Commit**: `829cde463e90c5bc042ed37e3bc84edf221edfb1`
**Title**: API Gateway Standardization Plan

---

## Overview

This PR contains a comprehensive implementation plan for standardizing API Gateway as the primary entry point for all services (Lambda and App Runner), while maintaining support for direct access in local development environments.

## What's Included

📄 **Complete Implementation Plan** (`API_GATEWAY_STANDARDIZATION_PLAN.md`)
- 770 lines of detailed technical planning
- Architecture diagrams (current vs. proposed)
- Terraform module structure
- Bootstrap and IAM policy changes
- Migration strategy and timeline

## Key Questions Answered

### ✅ Is it necessary to change the bootstrap?
**YES** - Comprehensive API Gateway IAM policies are required for:
- REST API full CRUD operations
- Usage plans and API keys management
- VPC Links (for future private integrations)
- CloudWatch Logs configuration
- WAF association permissions
- Account settings management

### ✅ Is it necessary to change the deploy roles permissions?
**YES** - Deploy role permissions need enhancement for:
- Usage plans: `arn:aws:apigateway:*::/usageplans/*`
- API keys: `arn:aws:apigateway:*::/apikeys/*`
- VPC Links: `arn:aws:apigateway:*::/vpclinks/*`
- Account settings: `arn:aws:apigateway:*::/account`
- CloudWatch Logs management
- IAM role management for API Gateway CloudWatch Logs
- WAF association

## Proposed Architecture

### Current State
- Lambda Function URLs (direct access)
- App Runner URLs (direct access)
- API Gateway (optional)

### Future State
- **API Gateway** as the standard entry point (cloud deployments)
- **Rate limiting** (5000 burst, 10000/sec default)
- **Centralized security** (API keys, WAF, throttling)
- **Direct access** only for local development

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
                    └────────────┬───────────────────────┘
                                 │
                    ┌────────────┴───────────┐
                    │                        │
           ┌────────▼──────┐        ┌───────▼────────┐
           │  Lambda       │        │  App Runner    │
           │  (No URL)     │        │  (Public)      │
           └───────────────┘        └────────────────┘
```

## Terraform Module Structure

```
terraform/modules/
├── api-gateway-shared/          # Common configuration
│   ├── main.tf                  # REST API, stage, deployment
│   ├── throttling.tf            # Rate limiting, usage plans
│   ├── security.tf              # API keys, WAF integration
│   └── outputs.tf
│
├── api-gateway-lambda/          # Lambda integration (AWS_PROXY)
│   └── main.tf
│
└── api-gateway-apprunner/       # App Runner integration (HTTP_PROXY)
    └── main.tf
```

## Key Features

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

### Developer Experience
- ✅ Local development mode with direct access
- ✅ Feature flags for gradual migration
- ✅ Modular, reusable Terraform code
- ✅ Clear rollback strategy

## Configuration Examples

### Cloud Deployment (Standard)
```hcl
enable_api_gateway_standard = true
enable_direct_access        = false
api_throttle_burst_limit    = 5000
api_throttle_rate_limit     = 10000
enable_waf                  = false  # true for production
enable_xray_tracing         = true
```

### Local Development
```hcl
enable_api_gateway_standard = false
enable_direct_access        = true
```

## Implementation Phases

1. **Phase 1**: Module Creation (no breaking changes)
   - Create `modules/api-gateway-shared/`
   - Create `modules/api-gateway-lambda/`
   - Create `modules/api-gateway-apprunner/`

2. **Phase 2**: Bootstrap IAM policy updates
   - Add comprehensive API Gateway management policy
   - Attach to GitHub Actions roles

3. **Phase 3**: Application Terraform updates
   - Add new variables
   - Modify `api-gateway.tf` to use modules
   - Update `lambda.tf` for conditional Function URLs
   - Update `outputs.tf`

4. **Phase 4**: Environment configuration
   - Update `dev.tfvars`, `test.tfvars`, `prod.tfvars`
   - Create `local.tfvars` for local development

5. **Phase 5**: Deployment and verification
   - Deploy bootstrap changes
   - Deploy application changes
   - Verify endpoints
   - Document rollback procedure

## Migration Strategy

- **Gradual rollout** using feature flags (`enable_api_gateway_standard`, `enable_direct_access`)
- **Zero downtime** - direct access remains available during migration
- **Rollback plan** - set `enable_direct_access=true` to restore direct URLs
- **Testing strategy** for local vs. cloud deployments

## Timeline

| Task | Time Estimate |
|------|---------------|
| Module creation | 2-3 hours |
| Bootstrap updates | 1 hour |
| Application updates | 2 hours |
| Testing | 2-3 hours |
| Documentation | 1 hour |
| **Total** | **~8-10 hours** |

## Benefits

### Cost Management
- Rate limiting prevents abuse
- Usage plans for cost control
- Consolidated logging (lower costs)

### Security
- Single entry point
- Centralized rate limiting
- WAF integration ready
- API key support

### Observability
- Centralized CloudWatch logging
- X-Ray tracing support
- Detailed access logs
- CloudWatch metrics per API

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing deployments | Use feature flags for gradual migration |
| Increased latency | API Gateway adds ~10-30ms - monitor and optimize |
| Increased costs | $3.50 per million requests - benefits outweigh costs |
| Module dependencies | Thorough testing with `terraform plan` |

## Next Steps

This PR contains **only the plan document** for review and discussion.

Once approved, follow-up PRs will implement:
1. ✅ Bootstrap IAM policy changes
2. ✅ Terraform modules creation
3. ✅ Application infrastructure updates
4. ✅ Environment configuration updates
5. ✅ Documentation updates

## Review Checklist

- [ ] Review architecture changes
- [ ] Approve module structure
- [ ] Confirm bootstrap changes needed
- [ ] Approve migration strategy
- [ ] Review timeline estimate
- [ ] Approve for implementation

## Files Changed

- ✅ `API_GATEWAY_STANDARDIZATION_PLAN.md` (new, 770 lines)

## Related Branches

- **This plan**: `claude/api-gateway-standard-01PqDN99TX3Noq24Q9BEs3uR`
- App Runner integration: `claude/apprunner-api-gateway-01PqDN99TX3Noq24Q9BEs3uR`
- AWS services access: `claude/enable-aws-services-01PqDN99TX3Noq24Q9BEs3uR`

---

**Ready for Review**: This comprehensive plan is ready for team review and approval before implementation begins.

To create the PR on GitHub, visit:
https://github.com/gpazevedo/aws-base/pull/new/claude/api-gateway-standard-01PqDN99TX3Noq24Q9BEs3uR
