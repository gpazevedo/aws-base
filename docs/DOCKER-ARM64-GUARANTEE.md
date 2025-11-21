# Docker ARM64 Architecture Guarantee

## Overview

**All Docker images published to Amazon ECR are guaranteed to use arm64 (aarch64) architecture for AWS Graviton2 processors.**

This is enforced at multiple levels to ensure consistency and prevent accidental deployments of x86_64 images to AWS services.

---

## Why ARM64?

AWS Graviton2 processors (arm64 architecture) provide:

- ✅ **Better price-performance**: Up to 40% better price-performance than x86_64
- ✅ **Energy efficiency**: Lower power consumption
- ✅ **Native support**: AWS Lambda, App Runner, and EKS all support Graviton2
- ✅ **Future-proof**: AWS is investing heavily in Graviton processors

**All ECR images in this project target arm64 to maximize these benefits.**

---

## Enforcement Mechanisms

### 1. **Hardcoded in docker-push.sh**

The primary enforcement is in `scripts/docker-push.sh`:

```bash
# =============================================================================
# IMPORTANT: ECR images MUST always be arm64 for AWS Graviton2
# This is hardcoded and cannot be overridden to ensure consistency across:
# - AWS Lambda (Graviton2 processors)
# - AWS App Runner (arm64 instances)
# - AWS EKS (Graviton2 nodes)
#
# DO NOT modify this value. Local testing with other architectures should
# use 'make docker-build ARCH=amd64' which does NOT push to ECR.
# =============================================================================
TARGET_ARCH="arm64"  # REQUIRED: Always build for arm64 (AWS Graviton2)
```

**This value is hardcoded and has no override mechanism.**

### 2. **All ECR Push Commands Use docker-push.sh**

Every method of pushing to ECR uses the same script:

| Command | Script Called | Architecture |
|---------|---------------|--------------|
| `make docker-push-dev` | `docker-push.sh` | ✅ arm64 |
| `make docker-push-test` | `docker-push.sh` | ✅ arm64 |
| `make docker-push-prod` | `docker-push.sh` | ✅ arm64 |
| GitHub Actions (Lambda) | `docker-push.sh` | ✅ arm64 |
| GitHub Actions (App Runner) | `docker-push.sh` | ✅ arm64 |
| GitHub Actions (EKS) | `docker-push.sh` | ✅ arm64 |

**There is no way to push to ECR without using `docker-push.sh`.**

### 3. **QEMU Emulation for x86_64 Hosts**

When building on x86_64 machines, the script automatically:

1. Detects the host architecture
2. Installs QEMU emulation (one-time setup)
3. Uses Docker BuildKit to cross-compile for arm64
4. Pushes arm64 image to ECR

Example output:
```
🖥️  Detecting host architecture...
   Host CPU: x86_64
   Target: arm64 (AWS Graviton2)

⚠️  Cross-platform build detected (x86_64 → arm64)
   QEMU emulation required for arm64 builds

📦 Installing QEMU for cross-platform builds...
   This is a one-time setup
✅ QEMU installed successfully
```

### 4. **Visual Warnings in Makefile**

All ECR push commands display explicit warnings:

```
📤 Building and pushing Docker image to dev ECR (service: api)...
   ⚠️  IMPORTANT: Image will be built for arm64 architecture (AWS Graviton2)
```

---

## Local Testing with Different Architectures

For **local testing only**, you can build images with different architectures:

```bash
# Build for amd64 (local testing only - NOT pushed to ECR)
make docker-build ARCH=amd64

# Run locally
docker run -p 9000:8080 <YOUR-PROJECT>:amd64-latest
```

**Key points:**
- ✅ Useful for local development on x86_64 machines
- ✅ Faster builds (no emulation needed)
- ✅ Never pushed to ECR
- ❌ Cannot be used in AWS deployments

---

## Architecture Verification

### Check Image Architecture in ECR

```bash
# Get image manifest
aws ecr describe-images \
  --repository-name <YOUR-PROJECT> \
  --image-ids imageTag=api-dev-latest \
  --query 'imageDetails[0].imageManifestMediaType'

# Inspect image details
aws ecr batch-get-image \
  --repository-name <YOUR-PROJECT> \
  --image-ids imageTag=api-dev-latest \
  --query 'images[0].imageManifest' \
  --output text | jq '.config.architecture'
```

Expected output: `"arm64"` or `"aarch64"`

### Check Running Lambda Function Architecture

```bash
aws lambda get-function-configuration \
  --function-name <YOUR-PROJECT>-dev-api \
  --query 'Architectures'
```

Expected output: `["arm64"]`

### Check Docker Image Locally

```bash
docker image inspect <YOUR-PROJECT>:arm64-latest \
  --format '{{.Architecture}}'
```

Expected output: `arm64`

---

## CI/CD Pipeline

All GitHub Actions workflows enforce arm64:

```yaml
- name: Build and push Lambda Docker image
  run: |
    # Use centralized docker-push.sh script for consistent builds
    ./scripts/docker-push.sh ${{ env.ENVIRONMENT }} ${{ matrix.service }} Dockerfile.lambda
```

**No workflow can override the architecture.**

---

## Dockerfile Configuration

All Dockerfiles use multi-architecture base images with `TARGETPLATFORM`:

```dockerfile
ARG TARGETPLATFORM
FROM --platform=$TARGETPLATFORM public.ecr.aws/lambda/python:3.13
```

When `docker-push.sh` builds with `--platform=linux/arm64`:
- `TARGETPLATFORM` is automatically set to `linux/arm64`
- Both builder and runtime stages use arm64
- Python packages with C extensions are compiled for arm64

---

## Cost Savings

By using arm64 across all AWS services, you save:

| Service | Savings | Notes |
|---------|---------|-------|
| **Lambda** | ~20% | Graviton2 Lambda is cheaper per GB-second |
| **App Runner** | ~20% | arm64 instances cost less |
| **EKS** | ~30-40% | Graviton2 EC2 instances (t4g, m6g, c6g) |
| **ECR Transfer** | N/A | Same cost (no transfer between regions) |

**Example:** For a $500/month AWS bill, switching to Graviton2 could save $100-150/month.

---

## Migration from x86_64

If you previously used x86_64 and want to migrate:

### 1. Update Lambda Functions

```bash
# Build and push new arm64 image
./scripts/docker-push.sh dev api Dockerfile.lambda

# Update function to use arm64
aws lambda update-function-configuration \
  --function-name <YOUR-PROJECT>-dev-api \
  --architectures arm64

# Update function code
aws lambda update-function-code \
  --function-name <YOUR-PROJECT>-dev-api \
  --image-uri $ECR_URI:api-dev-latest
```

### 2. Update App Runner

App Runner automatically uses the image's architecture. Just deploy the new arm64 image.

### 3. Update EKS

For EKS, you need Graviton2 node groups:

```hcl
# terraform/eks.tf
node_groups = {
  main = {
    instance_types = ["t4g.medium", "t4g.large"]  # Graviton2
    # ...
  }
}
```

---

## Troubleshooting

### Build fails with "exec format error"

**Cause:** Trying to run arm64 image on x86_64 without QEMU emulation.

**Solution:**
```bash
# Install QEMU emulation
docker run --privileged --rm tonistiigi/binfmt --install all

# Or use amd64 for local testing
make docker-build-amd64
```

### Lambda fails with "Runtime exited with error: exec format error"

**Cause:** Lambda function architecture doesn't match image architecture.

**Solution:**
```bash
# Verify image architecture
aws ecr describe-images \
  --repository-name <YOUR-PROJECT> \
  --image-ids imageTag=api-dev-latest

# Update Lambda architecture
aws lambda update-function-configuration \
  --function-name <YOUR-PROJECT>-dev-api \
  --architectures arm64
```

### EKS pods stuck in "CrashLoopBackOff"

**Cause:** Node group is x86_64 but image is arm64 (or vice versa).

**Solution:**
```bash
# Check node architecture
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}'

# Ensure nodes are arm64 (Graviton2)
# Update EKS terraform to use t4g, m6g, or c6g instances
```

---

## Summary

| Question | Answer |
|----------|--------|
| **Can I push x86_64 images to ECR?** | ❌ No, docker-push.sh only allows arm64 |
| **Can I build x86_64 locally?** | ✅ Yes, for testing only (not pushed to ECR) |
| **Do GitHub Actions enforce arm64?** | ✅ Yes, all workflows use docker-push.sh |
| **Can I override the architecture?** | ❌ No, TARGET_ARCH is hardcoded |
| **What if I need x86_64?** | Use local builds only, never push to ECR |

---

## References

- [AWS Graviton2](https://aws.amazon.com/ec2/graviton/)
- [Lambda ARM64 Support](https://aws.amazon.com/blogs/compute/migrating-aws-lambda-functions-to-arm-based-aws-graviton2-processors/)
- [Docker Multi-Architecture](https://docs.docker.com/build/building/multi-platform/)
- [Docker BuildKit](https://docs.docker.com/build/buildkit/)

---

**Last Updated:** 2025-11-22
**Maintained By:** Project Team
