# Adding New Services

This guide explains how to add new Lambda and App Runner services using the provided automation scripts.

## ✅ Prerequisites

- Bootstrap infrastructure deployed (`make bootstrap-apply`)
- `uv` installed for Python package management
- Docker installed and running

---

## ⚡ Adding a Lambda Service

Lambda is best for APIs, event processing, and scheduled tasks.

### 1. Generate Infrastructure

Use the helper script to generate the Terraform configuration and API Gateway integration:

```bash
# Syntax: ./scripts/setup-terraform-lambda.sh <service-name> [enable_api_key]
./scripts/setup-terraform-lambda.sh worker true
```

**What happens:**

- Creates `terraform/lambda-worker.tf` (Lambda function definition).
- Appends integration to `terraform/api-gateway.tf` (routing `/worker/*` to this Lambda).

### 2. Create Application Code

Create your service directory in `backend/<service-name>`:

```bash
mkdir -p backend/worker
cp backend/api/main.py backend/worker/main.py
cp backend/api/pyproject.toml backend/worker/pyproject.toml
```

### 3. Deploy

Build the image and apply Terraform changes:

```bash
# 1. Build & Push (automatically builds arm64)
./scripts/docker-push.sh dev worker Dockerfile.lambda

# 2. Deploy
cd terraform
terraform apply -var-file=environments/dev.tfvars
```

### 4. Test

```bash
# Get API URL
PRIMARY_URL=$(terraform output -raw primary_endpoint)

# Test endpoint
curl $PRIMARY_URL/worker/health
```

---

## 🏃 Adding an App Runner Service

App Runner is best for long-running web apps, WebSockets, or high-concurrency services.

### 1. Generate Infrastructure

```bash
# Syntax: ./scripts/setup-terraform-apprunner.sh <service-name>
./scripts/setup-terraform-apprunner.sh web
```

**Prompts:**

- **Integrate with API Gateway?** (y/n): Choose 'y' to route `/web/*` through the main API Gateway, or 'n' for a standalone URL.

### 2. Create Application Code

Same as Lambda, but use `Dockerfile.apprunner` for building.

### 3. Deploy

```bash
# 1. Build & Push (automatically builds amd64)
./scripts/docker-push.sh dev web Dockerfile.apprunner

# 2. Deploy
cd terraform
terraform apply -var-file=environments/dev.tfvars
```

---

## ⚙️ Configuration

### Service Settings

Edit the generated `.tf` files to customize:

- **Memory/CPU**: `memory_size` (Lambda) or `instance_configuration` (App Runner).
- **Timeout**: `timeout` (Lambda).
- **Environment Variables**: Add to the `environment` block.

### Adding AWS Resources

To add SQS, DynamoDB, or S3, see [AWS-SERVICES-INTEGRATION.md](AWS-SERVICES-INTEGRATION.md).

### Type Checking for New Services

**Good news!** Type checking is automatically configured for all backend services through a custom pre-commit hook.

When you create a new service in `backend/<service-name>/`:

1. **Create pyrightconfig.json** in the service directory:

   ```bash
   cat > backend/<service-name>/pyrightconfig.json <<EOF
   {
     "venvPath": ".",
     "venv": ".venv"
   }
   EOF
   ```

2. **Type checking is automatic!** The pre-commit hook will:
   - Detect Python changes in your new service
   - Run `make typecheck SERVICE=<service-name>` automatically on commit
   - Use the service's isolated venv for accurate type checking

3. **Manual type check:**

   ```bash
   make typecheck SERVICE=<service-name>
   ```

**That's it!** No need to update `.pre-commit-config.yaml` or any other configuration files. The custom hook automatically discovers and type-checks all backend services.

See [PRE-COMMIT.md](PRE-COMMIT.md#multi-service-type-checking) for more details.

---

## 📝 Structured Logging for New Services

All backend services use **structlog** for structured JSON logging, which provides better searchability and analysis in CloudWatch Logs.

### Quick Start

When creating a new service, the logging configuration is **already included** in the example services. Simply copy from an existing service:

```bash
# Copy from existing service (api or runner)
cp backend/api/main.py backend/<service-name>/main.py
```

### What's Included

The copied `main.py` includes:

1. **Structlog configuration** - JSON output with ISO timestamps
2. **Request logging middleware** - Automatic request/response logging
3. **Context variables** - Bind request-specific data (path, method, client IP)
4. **Error logging** - Structured exception handling

### Example Log Output

```json
{
  "event": "request_completed",
  "path": "/api/health",
  "method": "GET",
  "status_code": 200,
  "duration_seconds": 0.042,
  "timestamp": "2025-01-20T12:34:56.789Z",
  "level": "info"
}
```

### Adding Custom Logs

Use structured logging throughout your service:

```python
import structlog

logger = structlog.get_logger()

# ✅ Good - structured
logger.info("user_created", user_id=user.id, username=user.name)

# ❌ Avoid - unstructured
logger.info(f"User {user.name} created with ID {user.id}")
```

### Dependencies

Structlog is included in the service dependencies. When you copy `pyproject.toml`:

```toml
dependencies = [
    "structlog>=24.4.0,<25.0.0",
]
```

Install dependencies:

```bash
cd backend/<service-name>
uv sync
```

### CloudWatch Queries

Search logs efficiently with structured fields:

```bash
# Find errors for a specific endpoint
aws logs filter-log-events \
  --log-group-name /aws/lambda/myproject-dev-<service> \
  --filter-pattern '{ $.level = "error" && $.path = "/api/users" }'

# Find slow requests
aws logs filter-log-events \
  --log-group-name /aws/lambda/myproject-dev-<service> \
  --filter-pattern '{ $.duration_seconds > 1 }'
```

### Best Practices

**DO:**

- ✅ Use consistent event names (e.g., `user_created`, `payment_processed`)
- ✅ Include relevant context (user_id, request_id, transaction_id)
- ✅ Use snake_case for field names
- ✅ Log errors with context and stack traces

**DON'T:**

- ❌ Log sensitive data (passwords, tokens, PII)
- ❌ Use string formatting: `logger.info(f"...")`
- ❌ Mix structured and unstructured logging

### More Information

For comprehensive documentation on structlog usage, configuration, and CloudWatch queries, see:

- [MONITORING.md - Structured Logging with Structlog](MONITORING.md#structured-logging-with-structlog)

---

## 🔍 Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues with deployments, Docker builds, and API Gateway.
