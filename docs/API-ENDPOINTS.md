# API Endpoints Documentation

This document describes all available endpoints in the FastAPI Lambda application and how to access them through API Gateway.

---

## 📚 Table of Contents

- [Available Endpoints](#available-endpoints)
- [API Gateway Architecture](#api-gateway-architecture)
- [Health Check Endpoints](#health-check-endpoints)
- [Application Endpoints](#application-endpoints)
- [Auto-Generated Documentation](#auto-generated-documentation)
- [Accessing via API Gateway](#accessing-via-api-gateway)
- [Local Development](#local-development)
- [Testing Endpoints](#testing-endpoints)

---

## API Gateway Architecture

This template uses a **modular API Gateway architecture** for better organization and reusability with **path-based routing** for multiple services.

### Modular Setup (Recommended)

The API Gateway configuration is split into reusable modules:

```
terraform/
├── api-gateway.tf                           # Orchestrates all integrations
├── modules/
│   ├── api-gateway-shared/                 # REST API, stage, deployment, API Keys
│   ├── api-gateway-lambda-integration/     # AWS_PROXY Lambda integration
│   └── api-gateway-apprunner-integration/  # HTTP_PROXY AppRunner integration
```

**Benefits:**

- ✅ Separation of concerns (shared resources vs. service-specific)
- ✅ Reusable across multiple Lambda and AppRunner services
- ✅ Built-in API Key authentication support
- ✅ Path-based routing (e.g., `/api/*`, `/worker/*`, `/apprunner/*`)
- ✅ Standardized CORS and logging configuration
- ✅ Easier to maintain and debug

**Integration Types:**

- `AWS_PROXY` - API Gateway forwards requests directly to Lambda
- `HTTP_PROXY` - API Gateway forwards requests to AppRunner services

**Path-Based Routing:**

- **Lambda 'api' service** → Root path: `/`, `/health`, `/greet`
- **Lambda 'worker' service** → `/worker/*` paths
- **AppRunner 'apprunner' service** → `/apprunner/*` paths
- **AppRunner 'web' service** → `/web/*` paths

For troubleshooting API Gateway issues, see **[API Gateway Troubleshooting Guide](TROUBLESHOOTING-API-GATEWAY.md)**.

---

## Available Endpoints

The FastAPI application provides the following endpoints:

### Health Check Endpoints

| Endpoint | Method | Description | Use Case |
|----------|--------|-------------|----------|
| `/health` | GET | Comprehensive health check with uptime | Monitoring, load balancer health checks |
| `/liveness` | GET | Kubernetes-style liveness probe | Container orchestration |
| `/readiness` | GET | Kubernetes-style readiness probe | Container orchestration |

### Application Endpoints

| Endpoint | Method | Description | Parameters |
|----------|--------|-------------|------------|
| `/` | GET | Root endpoint, welcome message | None |
| `/greet` | GET | Greet by name (query param) | `name` (query, optional) |
| `/greet` | POST | Greet by name (request body) | `name` (body, required) |
| `/error` | GET | Test error handling | None |

### Auto-Generated Documentation

FastAPI automatically generates interactive documentation:

| Endpoint | Description |
|----------|-------------|
| `/docs` | Swagger UI - Interactive API documentation |
| `/redoc` | ReDoc - Alternative API documentation |
| `/openapi.json` | OpenAPI schema (JSON) |

---

## Health Check Endpoints

### 1. `/health` - Comprehensive Health Check

**Purpose:** Provides detailed health information including uptime and version.

**Request:**
```bash
GET /health
```

**Response (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2025-01-20T12:34:56.789012+00:00",
  "uptime_seconds": 123.45,
  "version": "0.1.0"
}
```

**Response Fields:**
- `status`: Current health status (`healthy`)
- `timestamp`: ISO 8601 timestamp with timezone (UTC)
- `uptime_seconds`: Time since application started
- `version`: Application version

**Use Cases:**
- Load balancer health checks
- Monitoring and alerting systems
- Application status dashboards

---

### 2. `/liveness` - Liveness Probe

**Purpose:** Indicates if the application is running (Kubernetes-style probe).

**Request:**
```bash
GET /liveness
```

**Response (200 OK):**
```json
{
  "status": "alive"
}
```

**Use Cases:**
- Kubernetes liveness probes
- Container orchestration platforms
- Determining if a restart is needed

---

### 3. `/readiness` - Readiness Probe

**Purpose:** Indicates if the application is ready to receive traffic.

**Request:**
```bash
GET /readiness
```

**Response (200 OK):**
```json
{
  "status": "ready"
}
```

**Extensibility:**
You can extend this endpoint to check:
- Database connectivity
- External service availability
- Cache availability
- Required configuration presence

**Example Extension:**
```python
@app.get("/readiness", response_model=StatusResponse, tags=["Health"])
async def readiness_probe() -> StatusResponse:
    """Readiness probe with dependency checks."""
    # Check database
    try:
        db.ping()
    except Exception:
        raise HTTPException(status_code=503, detail="Database unavailable")

    # Check cache
    try:
        cache.ping()
    except Exception:
        raise HTTPException(status_code=503, detail="Cache unavailable")

    return StatusResponse(status="ready")
```

---

## Application Endpoints

### 1. `/` - Root Endpoint

**Purpose:** Welcome message and version information.

**Request:**
```bash
GET /
```

**Response (200 OK):**
```json
{
  "message": "Hello, World!",
  "version": "0.1.0"
}
```

---

### 2. `/greet` - Greeting (GET)

**Purpose:** Personalized greeting using query parameter.

**Request:**
```bash
GET /greet?name=Alice
```

**Parameters:**
- `name` (query, optional): Name to greet (default: "World")

**Response (200 OK):**
```json
{
  "message": "Hello, Alice!",
  "version": "0.1.0"
}
```

**Examples:**
```bash
# Default name
curl https://<YOUR-PROJECT>-api.execute-api.us-east-1.amazonaws.com/greet
# Response: {"message": "Hello, World!", "version": "0.1.0"}

# Custom name
curl https://<YOUR-PROJECT>-api.execute-api.us-east-1.amazonaws.com/greet?name=Alice
# Response: {"message": "Hello, Alice!", "version": "0.1.0"}
```

---

### 3. `/greet` - Greeting (POST)

**Purpose:** Personalized greeting using request body.

**Request:**
```bash
POST /greet
Content-Type: application/json

{
  "name": "Bob"
}
```

**Request Body:**
- `name` (string, required): Name to greet

**Response (200 OK):**
```json
{
  "message": "Hello, Bob!",
  "version": "0.1.0"
}
```

**Validation Error (422):**
```json
{
  "detail": [
    {
      "type": "missing",
      "loc": ["body", "name"],
      "msg": "Field required",
      "input": {}
    }
  ]
}
```

**Examples:**
```bash
# Valid request
curl -X POST https://<YOUR-PROJECT>-api.execute-api.us-east-1.amazonaws.com/greet \
  -H "Content-Type: application/json" \
  -d '{"name": "Bob"}'

# Invalid request (missing name)
curl -X POST https://<YOUR-PROJECT>-api.execute-api.us-east-1.amazonaws.com/greet \
  -H "Content-Type: application/json" \
  -d '{}'
# Response: 422 Validation Error
```

---

### 4. `/error` - Error Test Endpoint

**Purpose:** Test error handling and monitoring.

**Request:**
```bash
GET /error
```

**Response (500 Internal Server Error):**
```json
{
  "detail": "This is a test error"
}
```

**Use Cases:**
- Testing error monitoring systems
- Validating error handling pipelines
- Testing alerting configurations

---

## Auto-Generated Documentation

FastAPI automatically generates interactive API documentation that's always up-to-date with your code.

### Swagger UI (`/docs`)

**Access:** `https://<YOUR-PROJECT>-api-url/docs`

**Features:**
- Interactive API explorer
- Try endpoints directly from browser
- View request/response schemas
- See all available endpoints
- Test authentication (if configured)

**Screenshot:**
```
┌─────────────────────────────────────────────────┐
│ AWS Base Python API                      v0.1.0 │
├─────────────────────────────────────────────────┤
│                                                 │
│ Health                                          │
│   GET  /health     - Comprehensive health check │
│   GET  /liveness   - Liveness probe             │
│   GET  /readiness  - Readiness probe            │
│                                                 │
│ General                                         │
│   GET  /           - Root endpoint              │
│   GET  /greet      - Greet (query param)        │
│   POST /greet      - Greet (request body)       │
│   GET  /error      - Test error handling        │
│                                                 │
└─────────────────────────────────────────────────┘
```

### ReDoc (`/redoc`)

**Access:** `https://<YOUR-PROJECT>-api-url/redoc`

**Features:**
- Three-panel layout
- Better for documentation reading
- Cleaner interface
- Markdown support in descriptions
- Code samples in multiple languages

### OpenAPI Schema (`/openapi.json`)

**Access:** `https://<YOUR-PROJECT>-api-url/openapi.json`

**Features:**
- Machine-readable API specification
- OpenAPI 3.0 standard
- Import into tools like Postman, Insomnia
- Generate client libraries
- API versioning and documentation

**Example:**
```bash
# Download OpenAPI schema
curl https://<YOUR-PROJECT>-api-url/openapi.json > api-schema.json

# Use with Postman
# File → Import → api-schema.json

# Generate Python client
# openapi-generator-cli generate -i api-schema.json -g python
```

---

## Accessing via API Gateway

When deployed to AWS, your FastAPI application is accessible through API Gateway (standard for cloud deployments) or Lambda Function URLs (for local development).

### Getting Your API Endpoint

#### Option 1: API Gateway URL (Standard for Cloud Deployments)

API Gateway is the **standard entry point** for all cloud deployments, providing rate limiting, logging, security, and observability features.

**Get the URL:**
```bash
# Get primary endpoint from Terraform output (automatically selects correct URL)
cd terraform
terraform output primary_endpoint

# Get API Gateway specific URL
terraform output api_gateway_url

# Check deployment mode
terraform output deployment_mode
```

**URL Format:**
```
https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/
```

**Example:**
```bash
# Get primary endpoint
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

# Health check
curl $PRIMARY_URL/health

# Greet endpoint
curl "$PRIMARY_URL/greet?name=Alice"

# Interactive docs
open "$PRIMARY_URL/docs"  # macOS
xdg-open "$PRIMARY_URL/docs"  # Linux
```

**Features:**
- ✅ Rate limiting and throttling (configurable)
- ✅ **API Key authentication** (optional)
- ✅ CloudWatch access logs
- ✅ X-Ray distributed tracing
- ✅ CORS configuration
- ✅ WAF integration ready
- ✅ Custom domain support

#### Option 2: Lambda Function URL (Local Development Only)

Lambda Function URLs provide direct HTTP(S) access without API Gateway overhead. **Only enabled for local development** (`enable_direct_access = true`).

**Get the URL:**
```bash
# Get function URL from Terraform output (only when enable_direct_access = true)
cd terraform
terraform output lambda_function_url

# Or use AWS CLI
aws lambda get-function-url-config \
  --function-name <YOUR-PROJECT>-api-dev \
  --query 'FunctionUrl' \
  --output text
```

**URL Format:**
```
https://<unique-id>.lambda-url.<region>.on.aws/
```

**Example:**
```bash
# Test your Lambda via Function URL (local development)
FUNCTION_URL=$(cd terraform && terraform output -raw lambda_function_url)

# Health check
curl $FUNCTION_URL/health

# Greet endpoint
curl "$FUNCTION_URL/greet?name=Alice"

# Interactive docs
open "$FUNCTION_URL/docs"  # macOS
xdg-open "$FUNCTION_URL/docs"  # Linux
```

**When to use:**
- Local development and testing
- Fast iteration without API Gateway overhead
- Set `enable_direct_access = true` in `environments/local.tfvars`

**When NOT to use:**
- Production deployments (use API Gateway instead)
- Cloud environments requiring rate limiting
- When you need centralized logging and monitoring

### API Gateway Configuration

API Gateway is configured by default using Terraform modules. See [terraform/README.md](../terraform/README.md) for detailed configuration options.

**Key configuration variables** (`terraform/environments/{env}.tfvars`):

```hcl
# Enable API Gateway (standard for cloud)
enable_api_gateway_standard = true
enable_direct_access        = false

# Rate limiting
api_throttle_burst_limit = 5000  # Burst capacity
api_throttle_rate_limit  = 10000 # Requests per second

# Logging
api_log_retention_days = 7
api_logging_level      = "INFO"  # OFF, ERROR, INFO
enable_xray_tracing    = true

# CORS
cors_allow_origins = ["*"]
cors_allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
cors_allow_headers = ["Content-Type", "Authorization"]

# API Key authentication (optional)
enable_api_key              = false  # Set to true to enable
api_key_name                = "<YOUR-PROJECT>-dev-api-key"
api_usage_plan_quota_limit  = 10000   # Max requests per month
api_usage_plan_quota_period = "MONTH" # DAY, WEEK, or MONTH
```

### API Key Authentication

Enable API Key authentication to secure your API endpoints and track usage per key.

**Enable API Keys:**

Update your `terraform/environments/{env}.tfvars`:

```hcl
enable_api_key = true
api_key_name   = "<YOUR-PROJECT>-dev-api-key"

# Optional: Usage quotas
api_usage_plan_quota_limit  = 10000
api_usage_plan_quota_period = "MONTH"
```

**Retrieve API Key:**

```bash
# Get API Key value (sensitive)
cd terraform
terraform output -raw api_key_value

# Store in environment variable
export API_KEY=$(cd terraform && terraform output -raw api_key_value)
```

**Use API Key in requests:**

Include the `x-api-key` header in all requests:

```bash
# Health check with API Key
curl -H "x-api-key: $API_KEY" $PRIMARY_URL/health

# Greet endpoint with API Key
curl -H "x-api-key: $API_KEY" "$PRIMARY_URL/greet?name=Alice"

# POST request with API Key
curl -X POST -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
  $PRIMARY_URL/greet -d '{"name": "Bob"}'
```

**Features:**
- Rate limiting per API Key
- Usage tracking in CloudWatch
- Configurable quotas (daily/weekly/monthly)
- Easy rotation (recreate resource)
- Multiple keys support (manual configuration)

**Important Notes:**
- Header name must be `x-api-key` (lowercase)
- API Keys work only with API Gateway (not Lambda Function URLs)
- Store API Keys securely (environment variables, secrets managers)

**Architecture:**

The API Gateway implementation uses a modular architecture:
- `modules/api-gateway-shared/` - Shared API Gateway configuration (rate limiting, logging, security)
- `modules/api-gateway-lambda/` - Lambda integration (AWS_PROXY)
- `modules/api-gateway-apprunner/` - App Runner integration (HTTP_PROXY)

See [terraform/modules/*/README.md](../terraform/modules/) for module documentation

---

## Local Development

### Running Locally

**Option 1: Using uvicorn directly**
```bash
cd backend/api

# Install dependencies
uv sync

# Run development server
uv run python main.py

# Server starts at http://localhost:8000
```

**Option 2: Using uvicorn command**
```bash
cd backend/api
uv run uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

**Access endpoints:**
- API: http://localhost:8000
- Health: http://localhost:8000/health
- Docs: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Testing with Docker (Lambda Runtime)

**Build and run:**
```bash
# Build for local testing (amd64)
make docker-build-amd64 SERVICE=api

# Run locally
docker run -p 9000:8080 <YOUR-PROJECT>:amd64-latest

# Test in another terminal
curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -H "Content-Type: application/json" \
  -d '{
    "requestContext": {"http": {"method": "GET", "path": "/health"}},
    "rawPath": "/health",
    "headers": {}
  }'
```

---

## Testing Endpoints

### Using curl

```bash
# Health check
curl https://<YOUR-PROJECT>-api-url/health | jq

# Liveness
curl https://<YOUR-PROJECT>-api-url/liveness | jq

# Root endpoint
curl https://<YOUR-PROJECT>-api-url/ | jq

# Greet with query
curl "https://<YOUR-PROJECT>-api-url/greet?name=Alice" | jq

# Greet with POST
curl -X POST https://<YOUR-PROJECT>-api-url/greet \
  -H "Content-Type: application/json" \
  -d '{"name": "Bob"}' | jq

# Test error handling
curl https://<YOUR-PROJECT>-api-url/error | jq
```

### Using httpie

```bash
# Install httpie
pip install httpie

# Health check
http https://<YOUR-PROJECT>-api-url/health

# Greet with POST
http POST https://<YOUR-PROJECT>-api-url/greet name=Alice

# Interactive docs
http https://<YOUR-PROJECT>-api-url/docs
```

### Using Python

```python
import requests

BASE_URL = "https://<YOUR-PROJECT>-api-url"

# Health check
response = requests.get(f"{BASE_URL}/health")
print(response.json())

# Greet
response = requests.get(f"{BASE_URL}/greet", params={"name": "Alice"})
print(response.json())

# Greet POST
response = requests.post(f"{BASE_URL}/greet", json={"name": "Bob"})
print(response.json())
```

### Automated Testing

Run the test suite:
```bash
cd backend/api

# Install test dependencies
uv sync
uv pip install pytest pytest-cov

# Run tests
uv run pytest -v

# Run with coverage
uv run pytest --cov=. --cov-report=html
```

### Testing Multiple Services

When using path-based routing with multiple Lambda and AppRunner services:

```bash
# Get primary API Gateway endpoint
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

# Test Lambda services (root path routing)
curl $PRIMARY_URL/health              # 'api' service health
curl "$PRIMARY_URL/greet?name=Test"   # 'api' service endpoint
curl $PRIMARY_URL/worker/health       # 'worker' service health
curl $PRIMARY_URL/scheduler/status    # 'scheduler' service status

# Test AppRunner services (path prefix routing)
curl $PRIMARY_URL/apprunner/health    # AppRunner 'apprunner' service
curl "$PRIMARY_URL/apprunner/greet?name=Claude"  # AppRunner greet endpoint
curl $PRIMARY_URL/web/health          # AppRunner 'web' service
curl $PRIMARY_URL/admin/health        # AppRunner 'admin' service

# Or use make targets
make test-lambda-api                  # Test 'api' Lambda service
make test-lambda-worker               # Test 'worker' Lambda service
make test-apprunner-apprunner         # Test 'apprunner' AppRunner service
make test-apprunner-web               # Test 'web' AppRunner service
```

**Path Routing Rules:**

- First Lambda service (`api`) handles root path: `/`, `/health`, `/greet`, etc.
- Additional Lambda services use path prefix: `/worker/*`, `/scheduler/*`
- AppRunner services use path prefix: `/apprunner/*`, `/web/*`, `/admin/*`
- All services accessible through single API Gateway endpoint

---

## Next Steps

1. **Enable API Key Authentication**: Secure your API with API keys (see [API Key Authentication](#api-key-authentication) section above)
2. **Add Advanced Authentication**: Implement JWT, OAuth, or AWS Cognito for user-based authentication
3. **Add Database**: Connect to RDS, DynamoDB, or other databases
4. **Add Caching**: Implement Redis or ElastiCache
5. **Enhance Monitoring**: Configure CloudWatch dashboards, X-Ray, or third-party APM
6. **Custom Domain**: Use Route53 and ACM for custom domains
7. **CORS Configuration**: Configure for your specific frontend domain (already available)

---

## Resources

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Mangum Documentation](https://mangum.io/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [OpenAPI Specification](https://swagger.io/specification/)
