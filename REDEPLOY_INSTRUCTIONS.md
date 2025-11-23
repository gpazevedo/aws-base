# Lambda Redeploy Instructions

## Issue
The Lambda function is failing with: `Unable to import module 'main': No module named 'httpx'`

This happened because the Lambda was deployed before we added the `httpx` import and `/apprunner-health` endpoint.

## Solution: Rebuild and Redeploy

Run these commands from the project root on your **local machine** (where Docker is installed):

```bash
# 1. Rebuild and push the updated Lambda image (includes httpx import)
./scripts/docker-push.sh dev api Dockerfile.lambda

# 2. Wait for the image push to complete, then redeploy the Lambda
cd terraform
terraform apply -var-file=environments/dev.tfvars

# Or if you prefer using make:
cd /home/user/aws-base
make app-apply-dev
```

## What This Does

1. **Docker build**: Creates a new Lambda container image with:
   - Updated `main.py` that imports `httpx`
   - All dependencies including `httpx>=0.27.0`
   - The new `/apprunner-health` endpoint

2. **Push to ECR**: Uploads the image to your AWS Elastic Container Registry

3. **Terraform apply**: Updates the Lambda function to use the new image

## Verification

After redeployment, test the endpoints:

```bash
PRIMARY_URL=$(cd terraform && terraform output -raw primary_endpoint)

# Should work now
curl $PRIMARY_URL/health
curl $PRIMARY_URL/greet?name=World

# New endpoint (will return 503 if AppRunner not deployed, which is OK)
curl $PRIMARY_URL/apprunner-health
```

## Expected Results

- `/health` - Should return `{"status": "healthy", ...}`
- `/greet` - Should return `{"message": "Hello, World!", ...}`
- `/apprunner-health` - Will return either:
  - `503` with error message (if AppRunner service not deployed) ✅ This is expected
  - `200` with AppRunner response (if AppRunner is deployed)

## Note

The `/apprunner-health` endpoint is safe to have even without AppRunner deployed. It will gracefully return a 503 error when the service is unreachable.
