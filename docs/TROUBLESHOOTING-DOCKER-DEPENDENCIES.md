# Troubleshooting Docker Dependency Issues

## Problem: "No module named 'httpx'" or Missing Dependencies in Lambda/Container

This guide covers how to diagnose and fix Python dependency installation issues in Docker containers, particularly for AWS Lambda, App Runner, and EKS deployments.

---

## Table of Contents

1. [Understanding the Problem](#understanding-the-problem)
2. [Quick Fix](#quick-fix)
3. [Root Cause Analysis](#root-cause-analysis)
4. [Step-by-Step Diagnosis](#step-by-step-diagnosis)
5. [Dockerfile Verification](#dockerfile-verification)
6. [Testing Locally](#testing-locally)
7. [Forcing Lambda Update](#forcing-lambda-update)
8. [Prevention](#prevention)

---

## Understanding the Problem

### Common Error Messages

```json
{
  "errorMessage": "Unable to import module 'main': No module named 'httpx'",
  "errorType": "Runtime.ImportModuleError"
}
```

or

```json
{
  "message": "Internal server error"
}
```

### Why This Happens

Python dependencies are not properly installed or not accessible to the Python runtime in the container. This typically occurs when:

1. **Virtual environments are created** - Dependencies installed in venv instead of system Python
2. **Multi-stage builds miss dependencies** - Dependencies installed in builder stage but not copied to runtime
3. **Docker layer caching** - Old image layers cached, new changes not applied
4. **Lambda not updated** - New image pushed to ECR but Lambda still using old image

---

## Quick Fix

### For Lambda (Dockerfile.lambda)

1. **Rebuild without cache:**
   ```bash
   docker build --no-cache --platform=linux/arm64 \
     --build-arg SERVICE_FOLDER=api \
     -f backend/Dockerfile.lambda \
     -t test-lambda:latest backend/
   ```

2. **Push to ECR:**
   ```bash
   ./scripts/docker-push.sh dev api Dockerfile.lambda
   ```

3. **Force Lambda update:**
   ```bash
   # Get ECR image URI
   ECR_URI=$(cd terraform && terraform output -raw ecr_repository_url)
   LAMBDA_NAME=$(cd terraform && terraform output -raw lambda_function_name)

   # Update Lambda function
   aws lambda update-function-code \
     --function-name $LAMBDA_NAME \
     --image-uri $ECR_URI:api-dev-latest

   # Wait for update
   aws lambda wait function-updated --function-name $LAMBDA_NAME
   ```

4. **Test:**
   ```bash
   PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)
   curl "$PRIMARY_URL/health"
   ```

### For App Runner (Dockerfile.apprunner)

1. **Rebuild and push:**
   ```bash
   ./scripts/docker-push.sh dev apprunner Dockerfile.apprunner
   ```

2. **Update App Runner service** (via Terraform):
   ```bash
   cd terraform
   terraform apply -var-file="environments/dev.tfvars" -auto-approve
   ```

### For EKS (Dockerfile.eks)

1. **Rebuild and push:**
   ```bash
   ./scripts/docker-push.sh dev api Dockerfile.eks
   ```

2. **Update deployment:**
   ```bash
   kubectl rollout restart deployment/api -n <namespace>
   ```

---

## Root Cause Analysis

### The Correct Approach

All Dockerfiles use `uv pip compile` + `uv pip install` to install dependencies directly to system Python:

```dockerfile
# Set environment variables for uv
ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1

# Copy pyproject.toml
COPY ${SERVICE_FOLDER}/pyproject.toml ./

# Generate requirements from pyproject.toml and install
RUN uv pip compile pyproject.toml -o requirements.txt && \
    uv pip install --no-cache -r requirements.txt && \
    rm requirements.txt
```

**Why this works:**

- `UV_SYSTEM_PYTHON=1` - Forces uv to use system Python (no virtual environment)
- `uv pip compile` - Generates `requirements.txt` from `pyproject.toml`
- `uv pip install` - Installs directly to `/usr/local/lib/python3.13/site-packages` (Lambda) or system Python location
- Dependencies are in Python's default search path

### What Doesn't Work

❌ **Using `uv sync`:**
```dockerfile
RUN uv sync  # Creates virtual environment - Lambda can't access it
```

❌ **Using `uv pip install .`:**
```dockerfile
RUN uv pip install .  # Requires proper Python package structure
```

❌ **Installing in builder stage without copying dependencies (multi-stage builds):**
```dockerfile
FROM python:3.13-slim AS builder
RUN uv pip install ...

FROM python:3.13-slim
COPY --from=builder /app /app  # ❌ Dependencies not copied!
```

---

## Step-by-Step Diagnosis

### 1. Check CloudWatch Logs (Lambda)

```bash
LAMBDA_NAME=$(cd terraform && terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$LAMBDA_NAME --since 5m --format short
```

Look for:
- `Runtime.ImportModuleError`
- `No module named 'xxx'`
- Stack traces showing missing imports

### 2. Verify Dependencies in Container

```bash
# Get ECR image
ECR_URI=$(cd terraform && terraform output -raw ecr_repository_url)

# Check if dependencies are installed
docker run --rm --platform linux/arm64 \
  --entrypoint /bin/bash \
  $ECR_URI:api-dev-latest \
  -c "python -c 'import sys; print(sys.path)' && \
      ls -la /var/lang/lib/python3.13/site-packages/ | grep -E '(httpx|fastapi|uvicorn)'"
```

**Expected output:**
```
drwxr-xr-x  4 root root   4096 Nov 23 02:13 httpx
drwxr-xr-x  7 root root   4096 Nov 23 02:13 fastapi
drwxr-xr-x  8 root root   4096 Nov 23 02:13 uvicorn
```

### 3. Check Image Timestamps

```bash
# Check when image was last pushed to ECR
ECR_REPO=$(cd bootstrap && terraform output -raw ecr_repository_name)
aws ecr describe-images --repository-name $ECR_REPO \
  --query 'sort_by(imageDetails,& imagePushedAt)[-5:].[imagePushedAt, imageTags[0]]' \
  --output table
```

### 4. Check Lambda Image SHA

```bash
# Get currently deployed image SHA
LAMBDA_NAME=$(cd terraform && terraform output -raw lambda_function_name)
aws lambda get-function --function-name $LAMBDA_NAME \
  --query 'Code.ImageUri' --output text
```

Compare this with the ECR image SHA to ensure Lambda is using the latest image.

### 5. Test Import Locally

```bash
# Test if httpx can be imported
docker run --rm --platform linux/arm64 \
  --entrypoint python \
  $ECR_URI:api-dev-latest \
  -c "import httpx; print(f'httpx version: {httpx.__version__}')"
```

---

## Dockerfile Verification

### Dockerfile.lambda (Single-stage, Correct ✅)

```dockerfile
FROM --platform=$TARGETPLATFORM public.ecr.aws/lambda/python:3.13

ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1

COPY ${SERVICE_FOLDER}/pyproject.toml ./

# ✅ Correct: Installs to system Python
RUN uv pip compile pyproject.toml -o requirements.txt && \
    uv pip install --no-cache -r requirements.txt && \
    rm requirements.txt

COPY ${SERVICE_FOLDER}/ ./
CMD ["main.handler"]
```

**Location:** `/home/gpazevedo/genai/novo/backend/Dockerfile.lambda`

### Dockerfile.apprunner (Single-stage, Correct ✅)

```dockerfile
FROM --platform=$TARGETPLATFORM python:3.13-slim

ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1

COPY ${SERVICE_FOLDER}/pyproject.toml ./

# ✅ Correct: Installs to system Python
RUN uv pip compile pyproject.toml -o requirements.txt && \
    uv pip install --no-cache -r requirements.txt && \
    rm requirements.txt

COPY ${SERVICE_FOLDER}/ ./
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Location:** `/home/gpazevedo/genai/novo/backend/Dockerfile.apprunner`

### Dockerfile.eks (Multi-stage, Requires Special Handling ⚠️)

```dockerfile
# Build stage
FROM --platform=$TARGETPLATFORM python:3.13-slim AS builder

ENV UV_SYSTEM_PYTHON=1
ENV UV_COMPILE_BYTECODE=1

COPY ${SERVICE_FOLDER}/pyproject.toml ./
RUN uv pip compile pyproject.toml -o requirements.txt && \
    uv pip install --no-cache -r requirements.txt && \
    rm requirements.txt
COPY ${SERVICE_FOLDER}/ ./

# Runtime stage
FROM --platform=$TARGETPLATFORM python:3.13-slim

WORKDIR /app

# ✅ Copy application files
COPY --from=builder /app /app

# ✅ CRITICAL: Copy Python dependencies from builder
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**⚠️ Important:** Multi-stage builds MUST copy both `/app` AND the Python site-packages directory!

**Location:** `/home/gpazevedo/genai/novo/backend/Dockerfile.eks`

---

## Testing Locally

### Test Lambda Container Locally

```bash
# Build
docker build --platform=linux/arm64 \
  --build-arg SERVICE_FOLDER=api \
  -f backend/Dockerfile.lambda \
  -t test-lambda:latest backend/

# Run locally (requires Lambda Runtime Interface Emulator)
docker run --rm -p 9000:8080 \
  --platform linux/arm64 \
  test-lambda:latest

# Test (in another terminal)
curl -X POST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"rawPath": "/health", "requestContext": {"http": {"method": "GET"}}}'
```

### Test App Runner Container Locally

```bash
# Build
docker build --platform=linux/arm64 \
  --build-arg SERVICE_FOLDER=apprunner \
  -f backend/Dockerfile.apprunner \
  -t test-apprunner:latest backend/

# Run
docker run --rm -p 8080:8080 \
  --platform linux/arm64 \
  test-apprunner:latest

# Test
curl http://localhost:8080/health
```

### Test EKS Container Locally

```bash
# Build
docker build --platform=linux/arm64 \
  --build-arg SERVICE_FOLDER=api \
  -f backend/Dockerfile.eks \
  -t test-eks:latest backend/

# Run
docker run --rm -p 8000:8000 \
  --platform linux/arm64 \
  test-eks:latest

# Test
curl http://localhost:8000/health
```

---

## Forcing Lambda Update

### Problem: Terraform Says "No Changes"

When you rebuild an image with the same tag (e.g., `api-dev-latest`), Terraform won't detect a change because the tag hasn't changed.

### Solution 1: Force Update via AWS CLI

```bash
# Get values
ECR_URI=$(cd terraform && terraform output -raw ecr_repository_url)
LAMBDA_NAME=$(cd terraform && terraform output -raw lambda_function_name)

# Update function code
aws lambda update-function-code \
  --function-name $LAMBDA_NAME \
  --image-uri $ECR_URI:api-dev-latest

# Wait for update to complete
echo "Waiting for Lambda update..."
aws lambda wait function-updated --function-name $LAMBDA_NAME

# Check status
aws lambda get-function --function-name $LAMBDA_NAME \
  --query 'Configuration.LastUpdateStatus' --output text
```

### Solution 2: Use Timestamped Tags

The `docker-push.sh` script creates timestamped tags:

```bash
./scripts/docker-push.sh dev api Dockerfile.lambda
# Creates: api-dev-2025-11-23-02-20-7da3f25
```

Update Terraform to use specific tag:

```hcl
# terraform/lambda.tf
resource "aws_lambda_function" "api" {
  image_uri = "${data.aws_ecr_repository.app.repository_url}:api-dev-2025-11-23-02-20-7da3f25"
}
```

### Solution 3: Terraform Taint (Forces Recreate)

```bash
cd terraform
terraform taint aws_lambda_function.api
terraform apply -var-file="environments/dev.tfvars"
```

⚠️ **Warning:** This recreates the Lambda function (causes brief downtime).

---

## Prevention

### 1. Always Rebuild Without Cache for Production

```bash
# Add to CI/CD or deployment scripts
docker build --no-cache --platform=linux/arm64 ...
```

### 2. Use Timestamped Tags

Always use the timestamped tags created by `docker-push.sh`:

```bash
./scripts/docker-push.sh dev api Dockerfile.lambda
# Uses: api-dev-2025-11-23-02-20-7da3f25 (guaranteed unique)
```

### 3. Verify Dependencies After Build

```bash
# Add to your build script
docker run --rm --entrypoint python $IMAGE_URI -c "
import httpx
import fastapi
import uvicorn
print('✅ All dependencies imported successfully')
"
```

### 4. Monitor CloudWatch Logs

Set up CloudWatch alarms for Lambda errors:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name lambda-errors-${LAMBDA_NAME} \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=${LAMBDA_NAME}
```

### 5. Add Health Check in Dockerfile

All Dockerfiles include health checks:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1
```

This ensures the container can import Python modules and the app is running.

---

## Common Scenarios

### Scenario 1: "Works Locally, Fails in Lambda"

**Cause:** Different architectures (amd64 vs arm64) or different Python paths

**Solution:**
1. Build for correct architecture: `--platform=linux/arm64`
2. Test with Lambda's Python path: `/var/lang/lib/python3.13/site-packages`
3. Use Lambda base image for local testing: `public.ecr.aws/lambda/python:3.13`

### Scenario 2: "Worked Before, Broken After pyproject.toml Update"

**Cause:** Docker cached old dependency installation layer

**Solution:**
```bash
# Clear cache and rebuild
docker build --no-cache --platform=linux/arm64 \
  --build-arg SERVICE_FOLDER=api \
  -f backend/Dockerfile.lambda \
  -t $ECR_URI:api-dev-latest backend/

# Push to ECR
docker push $ECR_URI:api-dev-latest

# Force Lambda update
aws lambda update-function-code --function-name $LAMBDA_NAME --image-uri $ECR_URI:api-dev-latest
```

### Scenario 3: "Dependencies Installed, But Import Fails"

**Cause:** Multi-stage build not copying Python site-packages

**Solution:** For `Dockerfile.eks`, ensure you copy site-packages:

```dockerfile
# Runtime stage
COPY --from=builder /app /app
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
```

---

## Debugging Commands Reference

```bash
# Check CloudWatch logs
aws logs tail /aws/lambda/$LAMBDA_NAME --since 5m --follow

# List dependencies in container
docker run --rm --entrypoint /bin/bash $IMAGE_URI \
  -c "pip list"

# Check Python path
docker run --rm --entrypoint python $IMAGE_URI \
  -c "import sys; print('\n'.join(sys.path))"

# Test specific import
docker run --rm --entrypoint python $IMAGE_URI \
  -c "import httpx; print(f'httpx: {httpx.__version__}')"

# Check file locations
docker run --rm --entrypoint /bin/bash $IMAGE_URI \
  -c "find /usr/local/lib/python3.13 -name 'httpx*' -type d"

# Check Lambda function status
aws lambda get-function --function-name $LAMBDA_NAME \
  --query 'Configuration.[LastUpdateStatus,State,LastModified]' \
  --output table

# Get ECR image digest
aws ecr describe-images --repository-name $ECR_REPO \
  --image-ids imageTag=api-dev-latest \
  --query 'imageDetails[0].imageDigest' --output text
```

---

## Additional Resources

- [AWS Lambda Container Images](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html)
- [uv Documentation](https://github.com/astral-sh/uv)
- [Docker Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Python sys.path](https://docs.python.org/3/library/sys.html#sys.path)

---

## Related Documentation

- [DOCKER-ARCHITECTURE.md](DOCKER-ARCHITECTURE.md) - Architecture enforcement
- [TROUBLESHOOTING-API-GATEWAY.md](TROUBLESHOOTING-API-GATEWAY.md) - API Gateway issues
- [SCRIPTS.md](SCRIPTS.md) - Helper scripts documentation

---

**Last Updated:** 2025-11-23
**Issue:** Resolved Lambda import errors by fixing dependency installation approach
