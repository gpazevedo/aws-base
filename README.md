# AWS Bootstrap Infrastructure

> **Production-ready AWS infrastructure template for Python applications**

Bootstrap AWS projects with Python 3.13, `uv` dependency management, GitHub Actions CI/CD via OIDC, and Terraform state management. Supports Lambda, App Runner, and EKS deployment options.

**📖 New to this project?** See the [Terraform Bootstrap Guide](docs/INSTALLATION.md) for complete setup.

---

## 🚀 Features

### Compute Options
- **Lambda** - Serverless functions (< 15 min runtime)
- **App Runner** - Containerized web apps (long-running)
- **EKS** - Kubernetes orchestration (microservices)

### Core Stack
- Python 3.13 with `uv` package manager
- GitHub OIDC (no AWS credentials in CI/CD)
- Terraform with S3 state backend
- Multi-environment support (dev, test, prod)
- ECR with vulnerability scanning
- API Gateway with rate limiting & API keys

---

## 🎯 Quick Decision: Which Compute Option?

| Use Case | Choose | Why |
|----------|--------|-----|
| REST APIs, event processing | **Lambda** | Cost-effective, auto-scales, < 15min runtime |
| Web apps, long processes | **App Runner** | Simple, auto-scales, unlimited runtime |
| Complex microservices | **EKS** | Full control, Kubernetes features |

**Cost estimates:** Lambda ($5-50/mo) • App Runner ($20-100/mo) • EKS ($150-500/mo)

**Can't decide?** Start with Lambda - you can [add others later](docs/INCREMENTAL-ADOPTION.md).

---

## 📋 Prerequisites

- AWS Account with admin access
- [Terraform](docs/INSTALLATION.md#terraform) >= 1.13.0
- [AWS CLI](docs/INSTALLATION.md#aws-cli) configured
- [uv](docs/INSTALLATION.md#uv) for Python: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- GitHub repository

**📚 Detailed installation:** [INSTALLATION.md](docs/INSTALLATION.md)

---

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone git@github.com:gpazevedo/aws-base-python.git <YOUR-PROJECT>
cd <YOUR-PROJECT>
git remote remove origin

# Test Python setup (install dependencies with test extras)
cd backend/api && uv sync --extra test && cd ../..
make test
```

### 2. Configure

```bash
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
# Edit: project_name, github_org, github_repo, aws_region, enable_lambda
```

### 3. Deploy Bootstrap

```bash
aws sts get-caller-identity  # Verify AWS credentials
make bootstrap-create bootstrap-init bootstrap-apply
```

### 4. Deploy Application

```bash
make setup-terraform-backend

# Create Lambda service infrastructure for 'api' service
./scripts/setup-terraform-lambda.sh api false  # Disable API Key for quick start

# Build & push Docker image for 'api' service
./scripts/docker-push.sh dev api Dockerfile.lambda

# Deploy infrastructure
make app-init-dev app-apply-dev
```

### 5. Test Deployment

```bash
# Get endpoint
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

# Test API
curl $PRIMARY_URL/health
curl "$PRIMARY_URL/greet?name=World"
curl $PRIMARY_URL/docs  # OpenAPI docs

# Run test suite
make test-api
```

> **🔑 API Key:** Disabled by default for easier testing. Enable in production: `enable_api_key = true` in `terraform/environments/prod.tfvars`
>
> **📖 All endpoints:** [API-ENDPOINTS.md](docs/API-ENDPOINTS.md)

### 5a. Deploy Multiple Lambda Services (Path-Based Routing)

Add additional Lambda services behind the same API Gateway with automatic path-based routing:

```bash
# Create additional Lambda services (automatically appends to api-gateway.tf)
./scripts/setup-terraform-lambda.sh worker     # Creates /worker, /worker/*
./scripts/setup-terraform-lambda.sh scheduler  # Creates /scheduler, /scheduler/*

# Build & push images
./scripts/docker-push.sh dev worker Dockerfile.lambda
./scripts/docker-push.sh dev scheduler Dockerfile.lambda

# Deploy all services
make app-init-dev app-apply-dev
```

**API Gateway Path-Based Routing:**

- **'api' service** → Root path: `/`, `/health`, `/greet`, etc.
- **'worker' service** → `/worker`, `/worker/health`, `/worker/jobs`, etc.
- **'scheduler' service** → `/scheduler`, `/scheduler/health`, `/scheduler/tasks`, etc.

**Test multiple services:**

```bash
# Test all services through single API Gateway
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

curl $PRIMARY_URL/health           # 'api' service
curl $PRIMARY_URL/worker/health    # 'worker' service
curl $PRIMARY_URL/scheduler/health # 'scheduler' service

# Or use make targets
make test-lambda-api
make test-lambda-worker
```

> **💡 How it works:** The first Lambda service creates `api-gateway.tf` with shared gateway module. Additional services automatically append their integration modules to the same file.

### 5b. Deploy Multiple AppRunner Services (Optional)

Deploy AppRunner services for long-running web applications, microservices, or background workers:

```bash
# Create and deploy multiple AppRunner services
./scripts/setup-terraform-apprunner.sh web      # Web frontend service
./scripts/setup-terraform-apprunner.sh admin    # Admin dashboard
./scripts/setup-terraform-apprunner.sh worker   # Background worker

# When prompted, optionally add to API Gateway (if api-gateway.tf exists)
# y = Add to API Gateway with path-based routing (/web, /admin, /worker)
# N = Access directly via AppRunner URLs

# Build & push images for each service
./scripts/docker-push.sh dev web Dockerfile.apprunner
./scripts/docker-push.sh dev admin Dockerfile.apprunner
./scripts/docker-push.sh dev worker Dockerfile.apprunner

# Deploy all AppRunner services
make app-init-dev app-apply-dev
```

**Test individual AppRunner services:**

```bash
# Test specific services
make test-apprunner-web
make test-apprunner-admin
./scripts/test-apprunner.sh worker

# Get service URLs
cd terraform && terraform output apprunner_web_url
cd terraform && terraform output apprunner_admin_url
cd terraform && terraform output apprunner_worker_url
```

**Local testing (service-to-service communication):**

```bash
# Terminal 1: Web service
cd backend/web && uv run python main.py

# Terminal 2: Admin service
cd backend/admin && uv run python main.py

# Terminal 3: Test endpoints
curl http://localhost:8000/health    # Web service
curl http://localhost:8001/health    # Admin service
```

> **📖 Multi-service details:** Each AppRunner service gets its own `apprunner-<service>.tf` file and dedicated outputs
>
> **🔄 Service communication:** AppRunner services can communicate with Lambda functions via API Gateway or directly via service URLs

### 6. GitHub Actions (Optional)

Configure repository secrets (get ARNs from `make bootstrap-output`):
- `AWS_ACCOUNT_ID`, `AWS_REGION`
- `AWS_ROLE_ARN_DEV` (environment secret)
- `RELEASE_PLEASE_TOKEN` ([setup guide](docs/RELEASE-PLEASE.md))

Then push to deploy automatically:
```bash
git add . && git commit -m "Initial setup" && git push origin main
```

**✅ Done!** See [TERRAFORM-BOOTSTRAP.md](docs/TERRAFORM-BOOTSTRAP.md) for deep dive.

---

## 🐳 Docker & Multi-Architecture

ECR images use **architecture-specific builds** based on deployment target:

| Service | Architecture | Reason |
|---------|-------------|--------|
| **App Runner** | `amd64` (x86_64) | App Runner uses x86_64 instances |
| **Lambda** | `arm64` | Graviton2 processors (cost savings) |
| **EKS** | `arm64` | Graviton2 nodes (cost savings) |

```bash
# Local testing (any arch)
make docker-build-amd64  # For x86_64 machines
docker run -p 9000:8080 <YOUR-PROJECT>:amd64-latest

# Production (architecture auto-detected from Dockerfile)
./scripts/docker-push.sh dev api Dockerfile.apprunner  # Builds amd64
./scripts/docker-push.sh dev api Dockerfile.lambda     # Builds arm64
./scripts/docker-push.sh dev api Dockerfile.eks        # Builds arm64
```

**📖 Details:** [Docker Architecture Selection](docs/DOCKER-ARCHITECTURE.md)

---

## 🔧 Key Commands

### Bootstrap
```bash
make bootstrap-create    # Create S3 state bucket
make bootstrap-apply     # Deploy infrastructure
make setup-terraform-backend  # Generate backend configs
```

### Application
```bash
make app-init-dev        # Initialize Terraform
make app-apply-dev       # Deploy to dev
make docker-push-dev     # Build & push to ECR
make test-api            # Test deployed API
```

### Development
```bash
make test                # Run pytest
make lint                # Check with Ruff
make typecheck           # Type check with Pyright
make setup-pre-commit    # Install git hooks
```

**📖 Full list:** `make help` or [Makefile](Makefile)

---

## 📁 Directory Structure

```
aws-base/
├── bootstrap/           # One-time infrastructure (S3, OIDC, IAM, ECR)
├── terraform/           # Application infrastructure per environment
│   ├── environments/    # dev.tfvars, test.tfvars, prod.tfvars
│   └── resources/       # Lambda, API Gateway, etc.
├── backend/             # Python services
│   ├── api/            # FastAPI API service (Lambda/API Gateway)
│   │   ├── main.py
│   │   └── pyproject.toml
│   ├── apprunner/      # FastAPI AppRunner service
│   │   ├── main.py
│   │   └── pyproject.toml
│   ├── Dockerfile.lambda
│   ├── Dockerfile.apprunner
│   └── Dockerfile.eks
├── scripts/             # Automation scripts
├── docs/                # Documentation
└── k8s/                 # Kubernetes manifests (if using EKS)
```

**📖 Details:** [Directory structure guide](docs/TERRAFORM-BOOTSTRAP.md#directory-structure)

---

## 🏗️ Multi-Service Architecture

Organize services in `backend/`:

```bash
backend/
├── api/          # API service (Lambda/API Gateway)
├── apprunner/    # AppRunner service (long-running web app)
├── worker/       # Background worker
└── scheduler/    # Scheduled jobs
```

Build & deploy individually:
```bash
# Build and push a specific service
make docker-build SERVICE=apprunner
make docker-push-dev SERVICE=apprunner

# Or use the docker-push script directly
./scripts/docker-push.sh dev apprunner Dockerfile.apprunner
```

Images tagged: `{service}-{env}-{datetime}-{sha}` (e.g., `apprunner-dev-2025-11-22-abc1234`)

**Service-to-Service Communication:**

- Lambda services accessed via API Gateway root paths: `/health`, `/api-health`
- AppRunner services accessed via path prefix: `/apprunner/health`, `/web/health`, etc.
- Both services use `httpx` for async HTTP communication
- Configure service URLs via environment variables or API Gateway URL

---

## 🔐 Security

**Implemented:**
- S3 encryption & versioning
- GitHub OIDC (no long-lived credentials)
- ECR vulnerability scanning
- API Gateway rate limiting
- Least-privilege IAM policies

**Recommended:**
- Enable API Keys in production (`enable_api_key = true`)
- Use AWS Secrets Manager for sensitive data
- Enable CloudTrail & GuardDuty
- Review [Security Best Practices](docs/TERRAFORM-BOOTSTRAP.md#security)

---

## 📝 Configuration Examples

### Lambda API (Simple)
```hcl
# bootstrap/terraform.tfvars
enable_lambda = true
enable_api_gateway_standard = true  # API Gateway entry point
enable_api_key = true               # Require API keys
```

### App Runner (Web App)
```hcl
enable_apprunner = true
enable_api_gateway_standard = true
apprunner_cpu = "1024"
apprunner_memory = "2048"
```

### Hybrid (Lambda + App Runner)
```hcl
enable_lambda = true
enable_apprunner = true
ecr_repositories = ["web-frontend"]  # Additional ECR repo
```

**📖 More examples:** [Configuration Examples](docs/TERRAFORM-BOOTSTRAP.md#configuration-examples)

---

## 🆘 Troubleshooting

| Issue | Solution |
|-------|----------|
| Missing dependencies in Lambda | See [Docker Dependencies Guide](docs/TROUBLESHOOTING-DOCKER-DEPENDENCIES.md) |
| Bucket already exists | Change `state_bucket_name` (must be globally unique) |
| API Gateway 403 | Check Lambda permissions: `aws_lambda_permission.api_gateway` |
| No endpoint | Enable either `enable_api_gateway_standard` or `enable_direct_access` |
| Rate limiting | Adjust `api_throttle_burst_limit` in tfvars |
| EKS nodes not joining | Check security groups & VPC NAT gateway |

**📖 Guides:**
- [Docker Dependencies](docs/TROUBLESHOOTING-DOCKER-DEPENDENCIES.md) - Fix import errors
- [API Gateway](docs/TROUBLESHOOTING-API-GATEWAY.md) - API Gateway issues

---

## 📚 Documentation

### Getting Started
- [Installation Guide](docs/INSTALLATION.md) - Tool setup
- [Terraform Bootstrap](docs/TERRAFORM-BOOTSTRAP.md) - Complete walkthrough
- [API Endpoints](docs/API-ENDPOINTS.md) - API documentation

### Advanced
- [Incremental Adoption](docs/INCREMENTAL-ADOPTION.md) - Start small, scale later
- [Docker Multi-Arch](docs/DOCKER-MULTIARCH.md) - ARM64 builds
- [Pre-commit Hooks](docs/PRE-COMMIT.md) - Code quality
- [Release Please](docs/RELEASE-PLEASE.md) - Automated releases
- [Monitoring](docs/MONITORING.md) - CloudWatch & X-Ray

### Reference
- [Scripts Documentation](docs/SCRIPTS.md) - All helper scripts
- [Docker Architecture Selection](docs/DOCKER-ARCHITECTURE.md) - Architecture enforcement

---

## 📊 Cost Estimates

| Service | Cost/Month | Best For |
|---------|------------|----------|
| **Lambda** | $5-50 | Variable traffic, < 15min runtime |
| **App Runner** | $20-100 | Web apps (1 vCPU, 2GB) |
| **EKS** | $150-500 | Control plane ($73) + nodes |
| **Shared** | ~$5 | S3 state, ECR storage |

*Small app estimates. Actual costs vary by usage.*

---

## 🤝 Contributing

Contributions welcome! Fork, create feature branch, submit PR.

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 🙏 Acknowledgments

Built with [Terraform](https://www.terraform.io/), [uv](https://github.com/astral-sh/uv), and AWS best practices.

---

## 📞 Support

- 🐛 [Issues](https://github.com/<YOUR-ORG>/<YOUR-REPO>/issues)
- 💬 [Discussions](https://github.com/<YOUR-ORG>/<YOUR-REPO>/discussions)
- 📖 [Wiki](https://github.com/<YOUR-ORG>/<YOUR-REPO>/wiki)

---

**Built with ❤️ for the AWS + Python community**
