# Documentation Index

Complete documentation for the AWS Bootstrap Infrastructure project.

## Overview

- **[Executive Summary](../EXECUTIVE-SUMMARY.md)** - High-level overview for decision-makers and stakeholders

## Getting Started

- **[Installation Guide](INSTALLATION.md)** - Tool setup and prerequisites
- **[Terraform Bootstrap Guide](TERRAFORM-BOOTSTRAP.md)** - Complete walkthrough of infrastructure setup
- **[Adding Services](ADDING-SERVICES.md)** - Step-by-step guide to create new Lambda and AppRunner services
- **[AWS Services Integration](AWS-SERVICES-INTEGRATION.md)** - Integrate SQS, DynamoDB, S3, and other AWS services
- **[API Endpoints](API-ENDPOINTS.md)** - API documentation and testing

## Architecture

- **[Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md)** - Path-based routing for Lambda and AppRunner services
- **[Docker Guide](DOCKER.md)** - Architecture strategy, multi-arch builds, and troubleshooting

## Deployment

- **[GitHub Actions CI/CD](GITHUB-ACTIONS.md)** - Automated deployment workflows and configuration
- **[Incremental Adoption](INCREMENTAL-ADOPTION.md)** - Start small, add services incrementally
- **[Scripts Documentation](SCRIPTS.md)** - All helper scripts reference

## Testing

- **[Multi-Service Testing Guide](MULTI-SERVICE-TESTING-GUIDE.md)** - Comprehensive testing scenarios for API Gateway

## Configuration

- **[Service Configuration](SERVICE-CONFIGURATION.md)** - Service-specific configuration pattern using locals
- **[Pre-commit Hooks](PRE-COMMIT.md)** - Code quality automation
- **[Release Please](RELEASE-PLEASE.md)** - Automated releases and versioning
- **[Monitoring](MONITORING.md)** - CloudWatch, distributed tracing, and observability
- **[Tagging Strategy](TAGGING-STRATEGY.md)** - AWS resource tagging for cost allocation and organization

## Troubleshooting

- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Solutions for API Gateway, Docker, and deployment issues

## Quick Links

| Topic | Document |
|-------|----------|
| New to project? | [Installation Guide](INSTALLATION.md) |
| Deploy Lambda services | [Terraform Bootstrap](TERRAFORM-BOOTSTRAP.md) |
| Add AppRunner services | [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md) |
| Configure services | [Service Configuration](SERVICE-CONFIGURATION.md) |
| Setup CI/CD pipelines | [GitHub Actions](GITHUB-ACTIONS.md) |
| Test API endpoints | [API Endpoints](API-ENDPOINTS.md) |
| Build multi-arch Docker | [Docker Guide](DOCKER.md) |
| Fix common issues | [Troubleshooting Guide](TROUBLESHOOTING.md) |
| Add new services | [Adding Services](ADDING-SERVICES.md) |
| Integrate AWS services | [AWS Services Integration](AWS-SERVICES-INTEGRATION.md) |

## Recent Updates

### Service Configuration Pattern Migration (2025-12-04)

**Changes:**

- ✅ Migrated from centralized `tfvars` configs to service-local `locals` blocks
- ✅ Updated setup scripts to generate self-contained service configurations
- ✅ Each service now has its configuration in its own Terraform file
- ✅ Deployed s3vector Lambda service with Bedrock and S3 integration
- ✅ API Gateway supports API key authentication (enabled by default)

**Benefits:**

- Self-contained services - configuration lives with service definition
- Easier navigation - no hunting through large tfvars files
- Better version control - service changes isolated to service files
- More scalable - adding services doesn't bloat central configs

**Documentation:**

- Created [Service Configuration Guide](SERVICE-CONFIGURATION.md)
- Updated [.claude/README.md](../.claude/README.md) with current architecture
- Added s3vector service to deployed services list

### Multi-Service API Gateway Implementation (2025-11-23)

**Completed:**

- ✅ Modular API Gateway architecture with path-based routing
- ✅ Support for multiple Lambda services behind single API Gateway
- ✅ Support for AppRunner services with API Gateway integration
- ✅ Automatic integration appending in setup scripts
- ✅ Implicit dependency management for deployment triggers
- ✅ AppRunner variable configuration
- ✅ Bootstrap AppRunner IAM role creation

**Key Features:**

- Single API Gateway entry point for all services
- Path-based routing: `/api/*`, `/worker/*`, `/apprunner/*`
- Idempotent setup scripts (safe to run multiple times)
- Modular Terraform structure for maintainability
- Complete testing suite with make targets

**Documentation:**

- Updated README with multi-service examples
- Created MULTI-SERVICE-ARCHITECTURE.md guide
- Updated API-ENDPOINTS.md with path routing
- Removed outdated implementation status docs

## Contributing

Documentation improvements welcome! When updating:
1. Keep examples working and tested
2. Update this index when adding new docs
3. Follow existing formatting patterns
4. Include code examples where helpful
