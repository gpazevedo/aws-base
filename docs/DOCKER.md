# Docker Guide

This guide covers the Docker architecture strategy, multi-architecture build system, and troubleshooting for the project.

## 🏗️ Architecture Strategy

The project uses a specific architecture strategy to optimize for cost and performance:

| Service | Architecture | Why? |
|---------|-------------|------|
| **Lambda** | `arm64` (Graviton2) | ~20% better price-performance, lower cost. |
| **EKS** | `arm64` (Graviton2) | Significant cost savings on EC2 instances. |
| **App Runner** | `amd64` (x86_64) | Native architecture for App Runner instances. |
| **Local Dev** | `amd64` or `arm64` | Matches your local machine for faster testing. |

### Automatic Enforcement
The architecture is **automatically enforced** by the `scripts/docker-push.sh` script based on the Dockerfile name:
- `Dockerfile.lambda` → Builds `arm64`
- `Dockerfile.eks` → Builds `arm64`
- `Dockerfile.apprunner` → Builds `amd64`

You do not need to manually select the architecture for deployments.

---

## 🛠️ Multi-Architecture Builds

We use Docker BuildKit to support building images for different architectures, regardless of your host machine's CPU.

### How It Works
1. **Python Specifics**: Unlike compiled languages, Python requires dependencies (like `numpy` or `cryptography`) to be compiled for the **target** architecture, not the build machine.
2. **Dockerfiles**: Our Dockerfiles use `FROM --platform=$TARGETPLATFORM` to ensure the correct base image and binary compatibility.
3. **Emulation**: The build script automatically detects if QEMU emulation is needed (e.g., building `arm64` on an Intel Mac) and installs it if missing.

### Build Commands

**Production (Always uses correct architecture):**
```bash
# Push to dev environment
make docker-push-dev

# Push to prod environment
make docker-push-prod
```

**Local Testing (Matches your machine):**
```bash
# Build for your local architecture (fastest)
make docker-build-local

# Force specific architecture (for testing)
make docker-build ARCH=amd64
make docker-build ARCH=arm64
```

---

## 🔍 Troubleshooting

### Common Issues

#### 1. "exec format error"
**Cause:** Trying to run an `arm64` image on an `amd64` machine (or vice versa) without emulation.
**Solution:**
- For local testing, use `make docker-build-local` to build for your machine's architecture.
- If you need to run the production image locally, ensure QEMU is installed:
  ```bash
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
  ```

#### 2. "No module named 'httpx'" (or other dependencies)
**Cause:** Dependencies installed in a virtual environment or builder stage but not copied to the runtime stage/path.
**Solution:**
- Ensure `UV_SYSTEM_PYTHON=1` is set in Dockerfile.
- For multi-stage builds (EKS), ensure `site-packages` are copied:
  ```dockerfile
  COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
  ```
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed dependency debugging.

#### 3. Lambda "Runtime exited with error: exec format error"
**Cause:** Lambda function architecture configuration (`arm64`) doesn't match the Docker image architecture (`amd64`).
**Solution:**
- Ensure you used `scripts/docker-push.sh` (or `make docker-push`) which enforces `arm64` for Lambda.
- Verify Lambda config: `aws lambda get-function-configuration --function-name <name> --query 'Architectures'` should be `["arm64"]`.

---

## 📚 Reference

- **App Runner**: Uses `amd64` (x86_64) instances.
- **Lambda/EKS**: Uses `arm64` (Graviton2) for cost savings.
- **Build Script**: `scripts/docker-push.sh` handles all logic.
