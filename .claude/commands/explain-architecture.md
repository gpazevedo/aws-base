---
description: Explain the overall architecture of this AWS infrastructure project
---

Please explain the architecture of this AWS infrastructure project including:

1. **Bootstrap Infrastructure**: What gets deployed in the bootstrap phase (S3, ECR, IAM roles)

2. **Application Infrastructure**: What gets deployed per environment (Lambda, AppRunner, API Gateway)

3. **Multi-Service Architecture**: Current implementation
   - Path-based routing through single API Gateway
   - Lambda 'api' service (root path)
   - AppRunner 'apprunner' service (/apprunner/*)
   - How to add more services

4. **API Gateway Integration**: Modular architecture
   - Shared module for common resources
   - Lambda integration module (AWS_PROXY)
   - AppRunner integration module (HTTP_PROXY)
   - Path routing strategy

5. **Terraform Modules**: Structure and benefits
   - `modules/api-gateway-shared/`
   - `modules/api-gateway-lambda-integration/`
   - `modules/api-gateway-apprunner-integration/`

6. **Multi-Service Backend**: Directory organization
   - `backend/api/` - Lambda service
   - `backend/apprunner/` - AppRunner service
   - Pattern for adding new services

7. **Container Images**: Multi-architecture strategy
   - Lambda: arm64 (Graviton2)
   - AppRunner: amd64 (x86_64)
   - Tag format: `{service}-{env}-latest`

8. **Current Deployment Status**:
   - API Gateway URL and path routing
   - Deployed services and health endpoints
   - Testing commands

Provide a clear overview with examples, suitable for someone new to the project. Reference the MULTI-SERVICE-ARCHITECTURE.md document.
