# AWS Bootstrap Infrastructure

> **Production-ready AWS infrastructure template for Python applications**

Bootstrap AWS projects with Python 3.14, `uv` dependency management, GitHub Actions CI/CD via OIDC, and Terraform state management. Supports Lambda, App Runner, and EKS deployment options with multi-service architecture.

**📖 New to this project?**

- [Executive Summary](EXECUTIVE-SUMMARY.md) - High-level overview for decision-makers
- [Installation Guide](docs/INSTALLATION.md) - Complete setup and prerequisites
- [Multi-Service Architecture](docs/MULTI-SERVICE-ARCHITECTURE.md) - Technical architecture guide

---

## 🚀 Features

### Compute Options

- **Lambda** - Serverless functions (< 15 min runtime)
- **App Runner** - Containerized web apps (long-running)
- **EKS** - Kubernetes orchestration (microservices)

### Core Stack

- Python 3.14 with `uv` package manager
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
- [Python](docs/INSTALLATION.md#python) >= 3.11
- [Git](docs/INSTALLATION.md#git)
- [uv](docs/INSTALLATION.md#uv-python-package-manager) (Python Package Manager)
- [Pyright](docs/INSTALLATION.md#pyright-type-checker) (Type Checker)
- [Ruff](docs/INSTALLATION.md#ruff-python-linterformatter) (Linter/Formatter)
- [Make](docs/INSTALLATION.md#make)
- [Docker](docs/INSTALLATION.md#docker)
- [AWS CLI](docs/INSTALLATION.md#aws-cli)
- [Terraform](docs/INSTALLATION.md#terraform) >= 1.13.0
- [tflint](docs/INSTALLATION.md#tflint-terraform-linter) (Terraform Linter)
- GitHub repository

**📚 Detailed installation:** [INSTALLATION.md](docs/INSTALLATION.md)

---

## 🚀 Quick Start

> **📝 Note:** This repository includes two example services (`api` and `runner`) to demonstrate the multi-service architecture capabilities. The `api` service (Lambda) and `runner` service (AppRunner) show how different AWS compute options can work together. You can use these as templates to build your own services or replace them entirely.

### 1. Clone and Setup

```bash
git clone git@github.com:gpazevedo/aws-base-python.git <YOUR-PROJECT>
cd <YOUR-PROJECT>
git remote remove origin

# Install dependencies for all services (includes test dependencies for type checking)
cd backend/api && uv sync --extra test && cd ../..
cd backend/runner && uv sync --extra test && cd ../..

# Verify setup
make test
```

> **⚠️ Important:** Always run `uv sync --extra test` to install test dependencies (pytest, pytest-cov, etc.). This is required for type checking with pyright and running tests. Without test dependencies, you'll see import errors like "Import 'pytest' could not be resolved".

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

### 4. Setup Terraform Backend

Create the backend configuration that all environments will use:

```bash
make setup-terraform-backend
```

### 5. Deploy API Service (Lambda Example)

Start with the API service to learn the basics:

```bash
# Step 1: Create Lambda service infrastructure for 'api' service
./scripts/setup-terraform-lambda.sh api false  # Disable API Key for quick start

# Step 2: Build & push Docker image for 'api' service
./scripts/docker-push.sh dev api Dockerfile.lambda

# Step 3: Deploy infrastructure
make app-init-dev app-apply-dev
```

### 6. Test API Service

```bash
# Get endpoint
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

# Test API service endpoints (note: all services use explicit path prefixes)
curl $PRIMARY_URL/api/health
curl "$PRIMARY_URL/api/greet?name=World"
curl $PRIMARY_URL/api/docs  # OpenAPI docs

# Run test suite
make test-api
```

> **🔑 API Key:** Disabled by default for easier testing. Enable in production: `enable_api_key = true` in `terraform/environments/prod.tfvars`
>
> **📖 All endpoints:** [API-ENDPOINTS.md](docs/API-ENDPOINTS.md)

### 7. Deploy Runner Service (AppRunner Example)

Now add the runner service to demonstrate service-to-service communication:

```bash
# Step 1: Create AppRunner service infrastructure for 'runner' service
./scripts/setup-terraform-apprunner.sh runner false  # Disable API Key for quick start

# When prompted, optionally add to API Gateway
# y = Add to API Gateway with path /runner (recommended for this example)
# N = Access directly via AppRunner URL

# Step 2: Build & push Docker image for 'runner' service
./scripts/docker-push.sh dev runner Dockerfile.apprunner

# Step 3: Deploy runner service
make app-init-dev app-apply-dev
```

### 8. Test Runner Service

```bash
# Get runner service URL
RUNNER_URL=$(cd terraform && terraform output -raw apprunner_runner_url)

# Test runner service directly
curl $RUNNER_URL/health
curl "$RUNNER_URL/greet?name=Runner"
```

### 9. Test Service-to-Service Communication

The API service has an `/inter-service` endpoint that calls other services, demonstrating how services can communicate:

```bash
# Get API Gateway endpoint and Runner URL
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)
RUNNER_URL=$(cd terraform && terraform output -raw apprunner_runner_url)

# API service calls runner service's /health endpoint
curl "$PRIMARY_URL/inter-service?service_url=${RUNNER_URL}/health" | jq

# This shows:
# - HTTP communication between Lambda and AppRunner
# - Response time tracking
# - Generic inter-service communication pattern
```

**Expected response:**

```json
{
  "service_response": {
    "status": "healthy",
    "timestamp": "2025-11-24T10:30:00.123456+00:00",
    "uptime_seconds": 120.45,
    "version": "0.1.0",
    "service_name": "runner"
  },
  "status_code": 200,
  "response_time_ms": 45.67,
  "target_url": "https://<unique-id>.us-east-1.awsapprunner.com/health"
}
```

> **🔄 Inter-Service Communication:** The `/inter-service` endpoint accepts any service URL as a query parameter, making it flexible for calling different services. No environment variables or hardcoded URLs needed - just pass the target URL when making the request.

### 10. Deploy S3Vector Service (Lambda with S3)

The s3vector service provides vector embedding storage in S3, enabling semantic search and similarity matching. It uses Amazon Bedrock Titan embeddings for text-to-vector conversion.

```bash
# Step 1: Create S3 bucket for vector storage
cp terraform/s3-vectors.tf.example terraform/s3-vectors.tf

# Step 2: Create Lambda service infrastructure for 's3vector' service
./scripts/setup-terraform-lambda.sh s3vector false  # Disable API Key for quick start

# Step 3: Install dependencies and build Docker image
cd backend/s3vector && uv sync --extra test && cd ../..
./scripts/docker-push.sh dev s3vector Dockerfile.lambda

# Step 4: Configure environment variables for s3vector service
# Edit terraform/lambda-s3vector.tf and add these to the environment.variables block:
#   BEDROCK_MODEL_ID    = "amazon.titan-embed-text-v2:0"
#   VECTOR_BUCKET_NAME  = aws_s3_bucket.vector_embeddings.id
# Note: AWS_REGION is automatically provided by Lambda runtime

# Step 5: Attach IAM policies for S3 and Bedrock access
# Add after the aws_lambda_function.s3vector resource in terraform/lambda-s3vector.tf:
#
# # Attach S3 vector storage policy from bootstrap
# data "terraform_remote_state" "bootstrap" {
#   backend = "s3"
#   config = {
#     bucket = var.terraform_state_bucket
#     key    = "bootstrap/terraform.tfstate"
#     region = var.aws_region
#   }
# }
#
# resource "aws_iam_role_policy_attachment" "s3vector_s3_access" {
#   role       = data.aws_iam_role.lambda_execution_s3vector.name
#   policy_arn = data.terraform_remote_state.bootstrap.outputs.s3_vector_service_policy_arn
# }
#
# resource "aws_iam_role_policy_attachment" "s3vector_bedrock_access" {
#   role       = data.aws_iam_role.lambda_execution_s3vector.name
#   policy_arn = data.terraform_remote_state.bootstrap.outputs.bedrock_invocation_policy_arn
# }

# Step 6: Deploy s3vector service and create S3 bucket
make app-init-dev app-apply-dev
```

> **📄 Template File:** See [terraform/s3-vectors.tf.example](terraform/s3-vectors.tf.example) for the complete S3 bucket configuration with versioning, encryption, public access blocking, and lifecycle policies.

**Configuration:**

- **S3 Bucket:** `${project_name}-${environment}-vector-embeddings` (created via Terraform)
- **Storage:** Embeddings stored as JSON files with original text and metadata
- **Bedrock Model:** Amazon Titan Text Embeddings V2 (1024 dimensions, pay-per-use)
- **Security:** Versioning enabled, encrypted at rest (AES256), public access blocked
- **IAM Permissions:** Configure via bootstrap policies (see Step 5 above)

### 11. Test S3Vector Service

This example demonstrates the complete workflow: text → embedding → storage → retrieval → text recovery.

> **🔀 API Gateway Routing:** After deploying the s3vector service, all services are accessed via explicit paths:
>
> - `/api/*` - API Lambda service
> - `/runner/*` - Runner AppRunner service
> - `/s3vector/*` - S3Vector Lambda service
>
> Requests to undefined paths (e.g., `/undefined`) will return 404 Not Found instead of being caught by a default service.

#### Setup

```bash
# Get API Gateway endpoint for s3vector service
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)
S3VECTOR_URL="$PRIMARY_URL/s3vector"
```

#### Health Check

```bash
# Verify service is running and S3 is configured
curl "$S3VECTOR_URL/health" | jq
```

**Expected response:**

```json
{
  "status": "healthy",
  "timestamp": "2025-12-04T10:30:00.123456+00:00",
  "version": "1.0.0",
  "bedrock_configured": true,
  "s3_configured": true
}
```

#### Complete Workflow Example

**Step 1: Store text with its embedding**

```bash
# Store a financial query with a mock embedding vector
# In production, use the /embeddings/generate endpoint (see section 12)
curl -X POST "$S3VECTOR_URL/embeddings/store" \
  -H "Content-Type: application/json" \
  -d '{
    "embedding_id": "financial-query-001",
    "text": "What are the best diversification strategies for a retirement portfolio?",
    "embedding": [
      0.023, -0.145, 0.312, 0.089, -0.234, 0.156, 0.401, -0.078,
      0.267, -0.189, 0.445, 0.134, -0.312, 0.223, 0.178, -0.256,
      0.389, -0.123, 0.467, 0.201, -0.378, 0.290, 0.156, -0.334,
      0.412, -0.167, 0.523, 0.078, -0.423, 0.334, 0.245, -0.401
    ],
    "metadata": {
      "category": "investment",
      "topic": "portfolio-management",
      "language": "en",
      "created_at": "2025-12-04T10:30:00Z"
    }
  }'
```

**Response:**

```json
{
  "success": true,
  "s3_key": "embeddings/financial-query-001.json",
  "bucket": "${project_name}-${environment}-vector-embeddings"
}
```

**Step 2: Retrieve the embedding and recover the original text**

```bash
# Retrieve by embedding_id - returns both the embedding and original text
curl "$S3VECTOR_URL/embeddings/financial-query-001" | jq
```

**Response:**

```json
{
  "embedding_id": "financial-query-001",
  "text": "What are the best diversification strategies for a retirement portfolio?",
  "embedding": [
    0.023, -0.145, 0.312, 0.089, -0.234, 0.156, 0.401, -0.078,
    0.267, -0.189, 0.445, 0.134, -0.312, 0.223, 0.178, -0.256,
    0.389, -0.123, 0.467, 0.201, -0.378, 0.290, 0.156, -0.334,
    0.412, -0.167, 0.523, 0.078, -0.423, 0.334, 0.245, -0.401
  ],
  "dimension": 32,
  "metadata": {
    "category": "investment",
    "topic": "portfolio-management",
    "language": "en",
    "created_at": "2025-12-04T10:30:00Z"
  }
}
```

> **💡 Use Case:** This demonstrates how to store and retrieve text with embeddings for semantic search. The embedding vector enables similarity matching, while the stored text allows you to recover the original content. In production, use the `/embeddings/generate` endpoint to automatically generate embeddings from text using Amazon Bedrock Titan (see section 12).

#### Verify Storage in S3

```bash
# Get the bucket name from Terraform outputs
VECTOR_BUCKET=$(cd terraform && terraform output -raw vector_embeddings_bucket_id)

# List all stored embeddings
aws s3 ls s3://$VECTOR_BUCKET/embeddings/

# Download and inspect the stored JSON
aws s3 cp s3://$VECTOR_BUCKET/embeddings/financial-query-001.json - | jq
```

#### API Documentation

Interactive API documentation is available:

- **Swagger UI:** `$S3VECTOR_URL/docs`
- **ReDoc:** `$S3VECTOR_URL/redoc`

**Available Endpoints:**

- `GET /s3vector/health` - Health check with configuration status
- `POST /s3vector/embeddings/store` - Store text with embedding vector
- `GET /s3vector/embeddings/{id}` - Retrieve embedding and original text
- `POST /s3vector/embeddings/generate` - Generate embeddings using Amazon Bedrock Titan

> **📝 Note:** The `/embeddings/generate` endpoint uses Amazon Bedrock Titan Text Embeddings V2. See section 12 below for usage examples and pricing.

### 12. Generate Embeddings with Amazon Bedrock

The s3vector service automatically generates embeddings from text using Amazon Bedrock Titan Text Embeddings V2. No infrastructure to deploy - just use the API!

#### Test Embedding Generation

```bash
# Generate embedding from text
curl -X POST "$S3VECTOR_URL/embeddings/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "What are the tax implications of withdrawing from a 401k early?"
  }'
```

**Expected response:**

```json
{
  "embedding": [
    0.0234, -0.1456, 0.3123, 0.0891, -0.2345, ..., 0.2451
  ],
  "dimension": 1024,
  "model": "amazon.titan-embed-text-v2:0",
  "text_length": 63,
  "processing_time_ms": 145.23,
  "stored_in_s3": false,
  "s3_key": null
}
```

> **📊 Model Details:** Amazon Titan Text Embeddings V2 generates 1024-dimensional vectors, supports up to 8K tokens, and provides state-of-the-art semantic search performance.

#### Generate and Store in One Step

You can generate an embedding and store it immediately:

```bash
# Generate embedding and store it in S3
curl -X POST "$S3VECTOR_URL/embeddings/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "What are the tax implications of withdrawing from a 401k early?",
    "embedding_id": "tax-query-001",
    "store_in_s3": true
  }'
```

**Response:**

```json
{
  "embedding": [0.0234, -0.1456, 0.3123, ..., 0.2451],
  "dimension": 1024,
  "model": "amazon.titan-embed-text-v2:0",
  "text_length": 63,
  "processing_time_ms": 152.67,
  "stored_in_s3": true,
  "s3_key": "embeddings/tax-query-001.json"
}
```

Now retrieve it:

```bash
curl "$S3VECTOR_URL/embeddings/tax-query-001"
```

#### Batch Processing Example

Generate and store multiple embeddings for a knowledge base:

```bash
# Store multiple financial advice embeddings
for query in \
  "How should I allocate my 401k investments?" \
  "What is the difference between traditional and Roth IRA?" \
  "When should I start taking Social Security benefits?"; do

  embedding_id=$(echo "$query" | md5sum | cut -d' ' -f1)

  curl -X POST "$S3VECTOR_URL/embeddings/generate" \
    -H "Content-Type: application/json" \
    -d "{
      \"text\": \"$query\",
      \"embedding_id\": \"$embedding_id\",
      \"store_in_s3\": true
    }" && echo

  sleep 0.5  # Rate limiting
done
```

#### Cost Information

Amazon Bedrock Titan Text Embeddings V2 uses pay-per-use pricing:

| Metric | Price | Example |
|--------|-------|---------|
| Per 1,000 input tokens | $0.00002 | 1M tokens = $0.02 |
| Average text (100 tokens) | $0.000002 | 1M texts = $2.00 |

**Example monthly costs:**

- **1M embeddings/month:** $2.00
- **10M embeddings/month:** $20.00
- **100M embeddings/month:** $200.00

> **💡 Best Practice:** Bedrock is ideal for development, testing, and production workloads with variable traffic. No infrastructure to manage, no idle costs, and automatic scaling.

### 13. Add More Services (Optional)

You can add as many Lambda and AppRunner services as needed. They all follow the same pattern:

**Add more Lambda services:**

```bash
# Step 1: Create additional Lambda services (automatically appends to api-gateway.tf)
./scripts/setup-terraform-lambda.sh worker     # Creates /worker, /worker/*
./scripts/setup-terraform-lambda.sh scheduler  # Creates /scheduler, /scheduler/*

# Step 2: Build & push images
./scripts/docker-push.sh dev worker Dockerfile.lambda
./scripts/docker-push.sh dev scheduler Dockerfile.lambda

# Step 3: Deploy all services
make app-init-dev app-apply-dev
```

**API Gateway Path-Based Routing:**

- **'api' service** → Root path: `/`, `/health`, `/greet`, etc.
- **'worker' service** → `/worker`, `/worker/health`, `/worker/jobs`, etc.
- **'scheduler' service** → `/scheduler`, `/scheduler/health`, `/scheduler/tasks`, etc.

**Test multiple Lambda services:**

```bash
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

curl $PRIMARY_URL/api/health       # 'api' service
curl $PRIMARY_URL/worker/health    # 'worker' service
curl $PRIMARY_URL/scheduler/health # 'scheduler' service

# Or use make targets
make test-lambda-api
make test-lambda-worker
```

**Add more AppRunner services:**

```bash
# Step 1: Create additional AppRunner services
./scripts/setup-terraform-apprunner.sh web      # Web frontend service
./scripts/setup-terraform-apprunner.sh admin    # Admin dashboard

# Step 2: Build & push images
./scripts/docker-push.sh dev web Dockerfile.apprunner
./scripts/docker-push.sh dev admin Dockerfile.apprunner

# Step 3: Deploy all AppRunner services
make app-init-dev app-apply-dev
```

**Test individual AppRunner services:**

```bash
# Test specific services
make test-apprunner-web
make test-apprunner-admin

# Get service URLs
cd terraform && terraform output apprunner_web_url
cd terraform && terraform output apprunner_admin_url
```

> **💡 How it works:** The first Lambda service creates `api-gateway.tf` with shared gateway module. Additional services automatically append their integration modules to the same file. Each AppRunner service gets its own `apprunner-<service>.tf` file and dedicated outputs.
>
> **🔄 Service communication:** Services can communicate with each other via API Gateway paths, direct AppRunner URLs, or Lambda Function URLs. Use Terraform outputs to get service URLs and pass them as parameters when calling the `/inter-service` endpoint.

### 13. GitHub Actions (Optional)

Configure repository secrets (get ARNs from `make bootstrap-output`):

- `AWS_ACCOUNT_ID`, `AWS_REGION`
- `AWS_ROLE_ARN_DEV` (environment secret)
- `RELEASE_PLEASE_TOKEN` ([setup guide](docs/RELEASE-PLEASE.md))

Then push to deploy automatically:

```bash
git add . && git commit -m "Initial setup" && git push origin main
```

**✅ Done!** See [GITHUB-ACTIONS.md](docs/GITHUB-ACTIONS.md) for deep dive.

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

**📖 Details:** [Docker Guide](docs/DOCKER.md)

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

```text
aws-base/
├── bootstrap/           # One-time infrastructure (S3, OIDC, IAM, ECR)
├── terraform/           # Application infrastructure per environment
│   ├── environments/    # dev.tfvars, test.tfvars, prod.tfvars
│   └── resources/       # Lambda, API Gateway, etc.
├── backend/             # Python services
│   ├── api/            # FastAPI API service (Lambda/API Gateway)
│   │   ├── main.py
│   │   └── pyproject.toml
│   ├── runner/          # FastAPI AppRunner service
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
├── runner/       # Runner service (AppRunner - long-running web app)
├── worker/       # Worker service (Lambda - background jobs)
└── scheduler/    # Scheduler service (Lambda - scheduled tasks)
```

Build & deploy individually:

```bash
# Build and push a specific service
make docker-build SERVICE=runner
make docker-push-dev SERVICE=runner

# Or use the docker-push script directly
./scripts/docker-push.sh dev runner Dockerfile.apprunner
```

Images tagged: `{service}-{env}-{datetime}-{sha}` (e.g., `runner-dev-2025-11-22-abc1234`)

**Service-to-Service Communication:**

- Lambda 'api' service accessed via root paths: `/health`, `/greet`
- Additional Lambda services accessed via path prefix: `/worker/health`, `/scheduler/status`
- AppRunner services accessed via path prefix: `/runner/health`, `/web/health`
- All services use `httpx` for async HTTP communication
- Service URLs available via Terraform outputs

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
apprunner_cpu = "512"
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
| Missing dependencies in Lambda | See [Troubleshooting Guide](docs/TROUBLESHOOTING.md) |
| Bucket already exists | Change `state_bucket_name` (must be globally unique) |
| API Gateway 403 | Check Lambda permissions: `aws_lambda_permission.api_gateway` |
| No endpoint | Enable either `enable_api_gateway_standard` or `enable_direct_access` |
| Rate limiting | Adjust `api_throttle_burst_limit` in tfvars |
| EKS nodes not joining | Check security groups & VPC NAT gateway |

**📖 Guides:**

- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Common issues and solutions

---

## 📚 Documentation

### Getting Started

- [Installation Guide](docs/INSTALLATION.md) - Tool setup
- [Terraform Bootstrap](docs/TERRAFORM-BOOTSTRAP.md) - Complete walkthrough
- [API Endpoints](docs/API-ENDPOINTS.md) - API documentation

### Advanced

- [GitHub Actions CI/CD](docs/GITHUB-ACTIONS.md) - Automated deployment workflows
- [Incremental Adoption](docs/INCREMENTAL-ADOPTION.md) - Start small, scale later

- [Pre-commit Hooks](docs/PRE-COMMIT.md) - Code quality
- [Release Please](docs/RELEASE-PLEASE.md) - Automated releases
- [Monitoring](docs/MONITORING.md) - CloudWatch & Distributed Tracing

### Reference

- [Scripts Documentation](docs/SCRIPTS.md) - All helper scripts
- [Docker Guide](docs/DOCKER.md) - Architecture enforcement

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
