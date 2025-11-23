# Docker Architecture Selection

## Overview

**Docker images published to Amazon ECR use architecture-specific builds based on the deployment target:**

- **App Runner**: `amd64` (x86_64) - App Runner uses x86_64 instances
- **Lambda**: `arm64` - AWS Graviton2 processors for cost savings
- **EKS**: `arm64` - Graviton2 nodes for cost savings

This is automatically enforced based on the Dockerfile being used, ensuring consistency and preventing architecture mismatches.

---

## Why ARM64 for Lambda and EKS?

AWS Graviton2 processors (arm64 architecture) provide:

- ✅ **Better price-performance**: Up to 40% better price-performance than x86_64
- ✅ **Energy efficiency**: Lower power consumption
- ✅ **Native support**: AWS Lambda and EKS fully support Graviton2
- ✅ **Future-proof**: AWS is investing heavily in Graviton processors

**Lambda and EKS images use arm64 to maximize these benefits.**

## Why AMD64 for App Runner?

AWS App Runner currently uses x86_64 instances:

- ✅ **Native compatibility**: No emulation overhead
- ✅ **Service requirement**: App Runner infrastructure is x86_64-based
- ✅ **Optimal performance**: Matches the underlying instance architecture

---

## Enforcement Mechanisms

### 1. **Automatic Detection in docker-push.sh**

The primary enforcement is in `scripts/docker-push.sh`:

```bash
# =============================================================================
# IMPORTANT: Architecture selection based on deployment target
# - AWS App Runner: amd64 (x86_64 instances)
# - AWS Lambda: arm64 (Graviton2 processors)
# - AWS EKS: arm64 (Graviton2 nodes)
#
# Architecture is automatically determined from the Dockerfile name.
# DO NOT modify this logic unless AWS services change their architectures.
# =============================================================================
if [[ "$DOCKERFILE" == *"apprunner"* ]]; then
  TARGET_ARCH="amd64"  # App Runner uses x86_64
else
  TARGET_ARCH="arm64"  # Lambda and EKS use Graviton2 (arm64)
fi
```

**Architecture is automatically selected based on the Dockerfile name - no manual override needed.**

### 2. **All ECR Push Commands Use docker-push.sh**

Every method of pushing to ECR uses the same script with automatic architecture detection:

| Command | Script Called | Architecture |
|---------|---------------|--------------|
| `./scripts/docker-push.sh dev api Dockerfile.apprunner` | `docker-push.sh` | ✅ amd64 |
| `./scripts/docker-push.sh dev api Dockerfile.lambda` | `docker-push.sh` | ✅ arm64 |
| `./scripts/docker-push.sh dev api Dockerfile.eks` | `docker-push.sh` | ✅ arm64 |
| GitHub Actions (Lambda) | `docker-push.sh` | ✅ arm64 |
| GitHub Actions (App Runner) | `docker-push.sh` | ✅ amd64 |
| GitHub Actions (EKS) | `docker-push.sh` | ✅ arm64 |

**Architecture is determined by the Dockerfile parameter - fully automated.**

### 3. **QEMU Emulation for Cross-Platform Builds**

The script automatically handles cross-platform builds:

1. Detects the host architecture (x86_64 or arm64)
2. Detects the target architecture (from Dockerfile)
3. Installs QEMU emulation if needed (one-time setup)
4. Uses Docker BuildKit to cross-compile
5. Pushes correctly-architected image to ECR

Example output (x86_64 → arm64):
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

Example output (arm64 → amd64):

```
🖥️  Detecting host architecture...
   Host CPU: arm64
   Target: amd64 (AWS App Runner x86_64)

⚠️  Cross-platform build detected (arm64 → amd64)
   QEMU emulation required for amd64 builds
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

By using the correct architecture for each service, you optimize costs:

| Service | Architecture | Savings | Notes |
|---------|-------------|---------|-------|
| **Lambda** | arm64 | ~20% | Graviton2 Lambda is cheaper per GB-second |
| **App Runner** | amd64 | N/A | Uses x86_64 infrastructure (native performance) |
| **EKS** | arm64 | ~30-40% | Graviton2 EC2 instances (t4g, m6g, c6g) |
| **ECR Transfer** | N/A | N/A | Same cost (no transfer between regions) |

**Example:** For Lambda and EKS workloads, switching to Graviton2 could save 20-40% on compute costs.

---

## Migration Guide

### Migrating Lambda from x86_64 to arm64

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

### Migrating App Runner to amd64

App Runner uses x86_64 infrastructure:

```bash
# Build and push amd64 image (automatically detected from Dockerfile.apprunner)
./scripts/docker-push.sh dev apprunner Dockerfile.apprunner

# Deploy - App Runner automatically uses the image's architecture
```

### Migrating EKS to arm64

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

Then build and push arm64 images:

```bash
./scripts/docker-push.sh dev api Dockerfile.eks
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
| **What architecture for App Runner?** | ✅ amd64 (x86_64) - automatically detected |
| **What architecture for Lambda?** | ✅ arm64 (Graviton2) - automatically detected |
| **What architecture for EKS?** | ✅ arm64 (Graviton2) - automatically detected |
| **Can I override the architecture?** | ❌ No, determined by Dockerfile name |
| **Do GitHub Actions enforce this?** | ✅ Yes, all workflows use docker-push.sh |
| **Can I build locally with different arch?** | ✅ Yes, for testing only (not pushed to ECR) |

---

## References

- [AWS Graviton2](https://aws.amazon.com/ec2/graviton/)
- [Lambda ARM64 Support](https://aws.amazon.com/blogs/compute/migrating-aws-lambda-functions-to-arm-based-aws-graviton2-processors/)
- [Docker Multi-Architecture](https://docs.docker.com/build/building/multi-platform/)
- [Docker BuildKit](https://docs.docker.com/build/buildkit/)

---

**Last Updated:** 2025-11-23
**Maintained By:** Project Team
