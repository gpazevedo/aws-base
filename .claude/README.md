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
- **Python 3.13** with `uv` for dependency management
- **Multi-service backend** architecture
- **API Gateway** as the standard entry point
- **GitHub Actions** for CI/CD via OIDC
- **Multi-architecture Docker** builds (arm64 for production, amd64 for local testing)

## Documentation

Comprehensive documentation is available in the `docs/` directory:
- [Terraform Bootstrap Guide](../docs/TERRAFORM-BOOTSTRAP.md)
- [API Endpoints](../docs/API-ENDPOINTS.md)
- [Docker Multi-Architecture](../docs/DOCKER-MULTIARCH.md)
- [Pre-commit Hooks](../docs/PRE-COMMIT.md)
- [Scripts Documentation](../docs/SCRIPTS.md)

## Configuration Files

- `.claude/commands/` - Custom slash commands
- `.claude/ignore` - Files and patterns to ignore in Claude Code context
- `.claude/README.md` - This file

## Tips

- Use `/help` to see all available Claude Code features
- Commands are context-aware and will use your current project state
- You can create custom commands by adding markdown files to `.claude/commands/`
