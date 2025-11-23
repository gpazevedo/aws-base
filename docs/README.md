# Documentation Index

Complete documentation for the AWS Bootstrap Infrastructure project.

## Getting Started

- **[Installation Guide](INSTALLATION.md)** - Tool setup and prerequisites
- **[Terraform Bootstrap Guide](TERRAFORM-BOOTSTRAP.md)** - Complete walkthrough of infrastructure setup
- **[API Endpoints](API-ENDPOINTS.md)** - API documentation and testing

## Architecture

- **[Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md)** - Path-based routing for Lambda and AppRunner services
- **[Docker Multi-Architecture](DOCKER-ARCHITECTURE.md)** - ARM64 vs AMD64 builds for different services
- **[Docker Multi-Arch Details](DOCKER-MULTIARCH.md)** - Detailed multi-architecture Docker guide

## Deployment

- **[Incremental Adoption](INCREMENTAL-ADOPTION.md)** - Start small, add services incrementally
- **[Scripts Documentation](SCRIPTS.md)** - All helper scripts reference

## Testing

- **[Multi-Service Testing Guide](MULTI_SERVICE_TESTING_GUIDE.md)** - Comprehensive testing scenarios for API Gateway

## Configuration

- **[Pre-commit Hooks](PRE-COMMIT.md)** - Code quality automation
- **[Release Please](RELEASE-PLEASE.md)** - Automated releases and versioning
- **[Monitoring](MONITORING.md)** - CloudWatch, X-Ray, and observability

## Troubleshooting

- **[API Gateway Troubleshooting](TROUBLESHOOTING-API-GATEWAY.md)** - Common API Gateway issues and solutions
- **[Docker Dependencies](TROUBLESHOOTING-DOCKER-DEPENDENCIES.md)** - Fix import errors and dependency issues

## Quick Links

| Topic | Document |
|-------|----------|
| New to project? | [Installation Guide](INSTALLATION.md) |
| Deploy Lambda services | [Terraform Bootstrap](TERRAFORM-BOOTSTRAP.md) |
| Add AppRunner services | [Multi-Service Architecture](MULTI-SERVICE-ARCHITECTURE.md) |
| Test API endpoints | [API Endpoints](API-ENDPOINTS.md) |
| Build multi-arch Docker | [Docker Architecture](DOCKER-ARCHITECTURE.md) |
| Fix API Gateway issues | [API Gateway Troubleshooting](TROUBLESHOOTING-API-GATEWAY.md) |

## Recent Updates

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
