---
description: Add a new backend service to the project (Lambda or AppRunner)
---

I want to add a new backend service to the project. Please help me:

1. Ask me for:
   - Service name (e.g., worker, scheduler, web, admin)
   - Service type: Lambda or AppRunner
   - Whether to integrate with API Gateway (path-based routing)

2. For Lambda services:
   - Run: `./scripts/setup-terraform-lambda.sh <service-name>`
   - Creates `terraform/lambda-<service>.tf`
   - Appends integration to `terraform/api-gateway.tf` (if exists)
   - Path routing: `/service-name/*` (or root for 'api')

3. For AppRunner services:
   - Run: `./scripts/setup-terraform-apprunner.sh <service-name>`
   - Creates `terraform/apprunner-<service>.tf`
   - Optionally appends to `terraform/api-gateway.tf`
   - Path routing: `/service-name/*`

4. Create backend code structure:
   - Directory: `backend/<service-name>/`
   - Copy and customize from existing service: main.py, pyproject.toml
   - Health endpoints: /health, /liveness, /readiness
   - Ensure Python 3.14 compatible Lambda handler (event loop management)

5. Build and deploy:
   - Lambda: `./scripts/docker-push.sh dev <service> Dockerfile.lambda`
   - AppRunner: `./scripts/docker-push.sh dev <service> Dockerfile.apprunner`
   - Apply: `cd terraform && terraform apply -var-file=environments/dev.tfvars`

6. Test the service:
   - Via API Gateway: `curl $PRIMARY_URL/<service>/health`
   - Direct (AppRunner): Check terraform outputs
   - Make target: `make test-<type>-<service>`

7. Explain the multi-service architecture and path-based routing

8. Optional AWS service integrations:
   - Bedrock (embeddings): Attach `bedrock_invocation_policy_arn` from bootstrap
   - S3 (vector storage): Attach `s3_vector_service_policy_arn` from bootstrap
   - DynamoDB, SQS, etc.: Add appropriate IAM policy attachments

Walk me through the entire process step by step.
