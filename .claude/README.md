# Claude Code Configuration

This directory contains custom commands and configuration for Claude Code to help you work with this AWS infrastructure project.

## Available Commands

Use these commands by typing `/command-name` in your Claude Code chat:

### Infrastructure & Deployment

- `/explain-architecture` - Get an overview of the project architecture
- `/bootstrap-infrastructure` - Deploy the bootstrap infrastructure from scratch
- `/deploy-dev` - Deploy to the dev environment
- `/setup-github-actions` - Configure GitHub Actions CI/CD

### Docker & Containers

- `/build-docker` - Build and push Docker images for a service
- `/explain-docker-multiarch` - Understand the multi-architecture Docker setup

### Testing & Quality

- `/test-api` - Test the deployed API endpoints
- `/lint-and-test` - Run code quality checks and tests
- `/troubleshoot-api-gateway` - Debug API Gateway issues

### Development

- `/add-service` - Add a new backend service to the project
- `/review-costs` - Analyze and optimize AWS costs

## Quick Start

1. **First Time Setup**: Run `/bootstrap-infrastructure` to deploy the foundational infrastructure
2. **Build & Deploy**: Use `/build-docker` and `/deploy-dev` to deploy your application
3. **Testing**: Use `/test-api` to verify your deployment
4. **Troubleshooting**: Use `/troubleshoot-api-gateway` if you encounter issues

## Project Context

This is an AWS infrastructure project with:

- **Compute Options**: Lambda (serverless), App Runner (containers), EKS (Kubernetes)
- **Python 3.14** with `uv` for dependency management
- **Multi-service architecture** with path-based routing
- **API Gateway** as single entry point for all services
- **GitHub Actions** for CI/CD via OIDC
- **Multi-architecture Docker** builds (arm64 for Lambda/EKS, amd64 for App Runner)

### Current Architecture (Multi-Service)

**Deployed Services:**

- Lambda 'api' service → Root path: `/`, `/health`, `/greet`
- Lambda 's3vector' service → Path: `/s3vector/*` (Bedrock Titan embeddings & S3 vector storage)
- AppRunner 'runner' service → Path: `/runner/*`

**Path-Based Routing:**

- API Gateway: `https://qyswzkhmw4.execute-api.us-east-1.amazonaws.com/dev`
- All services accessible through single gateway with API key authentication
- First Lambda service handles root, others use path prefixes

**Service Configuration Pattern:**

Each service's configuration is now in its own Terraform file using `locals` blocks:

- Lambda services: `terraform/lambda-{service}.tf` (e.g., `lambda-s3vector.tf`)
- App Runner services: `terraform/apprunner-{service}.tf` (e.g., `apprunner-runner.tf`)
- No more centralized service configs in `dev.tfvars` - each service is self-contained!

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- [Multi-Service Architecture](../docs/MULTI-SERVICE-ARCHITECTURE.md) - Path-based routing guide
- [Terraform Bootstrap Guide](../docs/TERRAFORM-BOOTSTRAP.md) - Complete setup walkthrough
- [API Endpoints](../docs/API-ENDPOINTS.md) - API documentation with testing
- [Docker Multi-Architecture](../docs/DOCKER-MULTIARCH.md) - Multi-arch builds
- [Documentation Index](../docs/README.md) - All documentation

## Configuration Files

- `.claude/commands/` - Custom slash commands
- `.claude/ignore` - Files and patterns to ignore in Claude Code context
- `.claude/README.md` - This file

## Tips

- Use `/help` to see all available Claude Code features
- Commands are context-aware and will use your current project state
- You can create custom commands by adding markdown files to `.claude/commands/`
