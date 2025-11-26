# Installation Guide

This guide provides step-by-step instructions for installing all required tools for this project on Linux (Ubuntu/Debian-based systems).

## Table of Contents

- [Python](#python)
- [Git](#git)
- [uv (Python Package Manager)](#uv-python-package-manager)
- [Pyright (Type Checker)](#pyright-type-checker)
- [Ruff (Python Linter/Formatter)](#ruff-python-linterformatter)
- [Make](#make)
- [Docker](#docker)
- [AWS CLI](#aws-cli)
- [Terraform](#terraform)
- [tflint (Terraform Linter)](#tflint-terraform-linter)
- [Verification](#verification)

---

## Python

**Minimum version required:** 3.11+
**Recommended version:** 3.14 (default for this project)

### Ubuntu/Debian

```bash
# Update package list
sudo apt update

# Install Python 3.11+
sudo apt install -y python3.11 python3.11-venv python3-pip

# Verify installation
python3.11 --version
```

### Alternative: Using deadsnakes PPA (for older Ubuntu versions)

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.11 python3.11-venv python3.11-dev
```

### Set as default (optional)

```bash
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
```

---

## Git

### Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y git

# Verify installation
git --version
```

### Configuration (first-time setup)

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

---

## uv (Python Package Manager)

**Official installer (recommended):**

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Add to PATH (add this to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.cargo/bin:$PATH"

# Reload shell configuration
source ~/.bashrc  # or source ~/.zshrc

# Verify installation
uv --version
```

### Alternative: Using pip

```bash
pip3 install uv
```

---

## uv Multi-Service Setup

This project supports **multiple Python services** in the `backend/` directory (e.g., `backend/api`, `backend/worker`). Here's how uv works with this architecture:

### ✅ Install uv Once, Manage Multiple Services

**You only need ONE global uv installation** to manage all Python services in the repository. Each service maintains its own:
- `pyproject.toml` - Service-specific dependencies
- `uv.lock` - Locked dependency versions
- `.venv/` - Isolated virtual environment

### Working with Multiple Services

```bash
# Clone the repository
git clone <repository-url>
cd aws-base-python

# Service 1: backend/api
cd backend/api
uv sync                    # Install api dependencies, creates .venv
uv run python main.py      # Run using api's environment

# Service 2: backend/worker (example future service)
cd ../worker
uv sync                    # Install worker dependencies, separate .venv
uv run python main.py      # Run using worker's environment

# Service 3: backend/scheduler (example future service)
cd ../scheduler
uv sync                    # Each service is completely independent
uv run python main.py
```

### Directory Structure

```
backend/
├── api/                   # API service
│   ├── pyproject.toml     # API dependencies (fastapi, boto3, etc.)
│   ├── uv.lock            # API locked versions
│   ├── .venv/             # API virtual environment (auto-created)
│   └── main.py
│
├── worker/                # Worker service (future)
│   ├── pyproject.toml     # Worker dependencies (celery, redis, etc.)
│   ├── uv.lock            # Worker locked versions
│   ├── .venv/             # Worker virtual environment
│   └── main.py
│
└── scheduler/             # Scheduler service (future)
    ├── pyproject.toml     # Scheduler dependencies (apscheduler, etc.)
    ├── uv.lock            # Scheduler locked versions
    ├── .venv/             # Scheduler virtual environment
    └── main.py
```

### Key Benefits

1. **Isolation**: Each service has its own dependencies and virtual environment
2. **Independence**: Services can use different library versions without conflicts
3. **Simplicity**: One `uv` command manages everything
4. **Speed**: uv is 10-100x faster than pip for dependency resolution
5. **Reproducibility**: `uv.lock` ensures consistent builds across environments

### Adding a New Service

To create a new Python service:

```bash
# 1. Create service directory
mkdir -p backend/my-service
cd backend/my-service

# 2. Copy template from existing service
cp ../api/pyproject.toml .
cp ../api/__init__.py .

# 3. Edit pyproject.toml
vim pyproject.toml
# Update: name = "my-service"
# Update: dependencies as needed

# 4. Create your service code
cat > main.py <<'EOF'
def handler(event, context):
    return {"statusCode": 200, "body": "My Service"}
EOF

# 5. Initialize and install dependencies
uv sync

# 6. Test locally
uv run python -c "from main import handler; print(handler({}, None))"
```

### Common Commands

```bash
# Install dependencies for current service
uv sync

# Add a new dependency
uv add boto3

# Add a dev dependency
uv add --dev pytest

# Update dependencies
uv sync --upgrade

# Run Python in the service's environment
uv run python main.py

# Run tests
uv run pytest

# Remove a dependency
uv remove package-name
```

### Why Not Use a Monorepo Tool?

This project uses **uv's built-in isolation** instead of monorepo tools like Poetry plugins or pipenv workspaces because:

- ✅ **Simpler**: Each service is an independent Python project
- ✅ **Standard**: Uses standard `pyproject.toml` (PEP 517/518)
- ✅ **Flexible**: Services can be extracted into separate repos later
- ✅ **Docker-friendly**: Each Dockerfile builds one service independently
- ✅ **uv-native**: No additional tooling needed

### Troubleshooting

**Issue**: `uv: command not found` after installation

```bash
# Add to PATH in ~/.bashrc or ~/.zshrc
export PATH="$HOME/.cargo/bin:$PATH"
source ~/.bashrc
```

**Issue**: Dependencies not installing in one service

```bash
# Ensure you're in the service directory
cd backend/api
pwd  # Should show: /path/to/aws-base-python/backend/api

# Remove lock file and retry
rm uv.lock
uv sync
```

**Issue**: Virtual environment conflicts between services

```bash
# uv automatically creates separate .venv for each service
# If you see conflicts, ensure you're running commands from the correct directory

# Check which Python is active
uv run which python
# Should show: /path/to/backend/api/.venv/bin/python (for api service)
```

---

## Pyright (Type Checker)

**Requires Node.js/npm**

### Install Node.js and npm first

```bash
# Install Node.js (LTS version)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
npm --version
```

### Install Pyright

```bash
# Global installation
sudo npm install -g pyright

# Verify installation
pyright --version
```

### Alternative: Using uv (project-local)

```bash
# Pyright is included in dev dependencies
uv pip install pyright
```

---

## Ruff (Python Linter/Formatter)

### Using uv (recommended)

```bash
uv tool install ruff

# Verify installation
ruff --version
```

### Alternative: Using pip

```bash
pip3 install ruff
```

### Alternative: Using cargo (Rust)

```bash
cargo install ruff
```

---

## Make

### Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y build-essential

# Verify installation
make --version
```

---

## Docker

### Ubuntu/Debian

```bash
# Remove old versions
sudo apt-get remove docker docker-engine docker.io containerd runc

# Install dependencies
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
sudo docker --version
docker compose version
```

### Post-installation steps

```bash
# Add your user to docker group (avoid using sudo)
sudo usermod -aG docker $USER

# Apply group changes (or logout/login)
newgrp docker

# Test Docker without sudo
docker run hello-world
```

### Enable QEMU for multi-architecture builds (optional)

```bash
# Required for building arm64 images on x86_64 machines
docker run --privileged --rm tonistiigi/binfmt --install all

# Verify
docker buildx ls
```

---

## AWS CLI

### Ubuntu/Debian

```bash
# Download installer
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Unzip
sudo apt-get install -y unzip
unzip awscliv2.zip

# Install
sudo ./aws/install

# Clean up
rm -rf aws awscliv2.zip

# Verify installation
aws --version
```

### Configuration

```bash
# Configure AWS credentials (interactive)
aws configure

# Or manually edit
mkdir -p ~/.aws
cat > ~/.aws/config <<EOF
[default]
region = us-east-1
output = json
EOF

cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
EOF

chmod 600 ~/.aws/credentials
```

**Note:** For this project, AWS authentication is primarily done via **GitHub Actions with OIDC**, so local AWS credentials are optional.

---

## Terraform

### Ubuntu/Debian

```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add HashiCorp repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install Terraform
sudo apt update
sudo apt install -y terraform

# Verify installation
terraform --version
```

### Alternative: Download binary directly

```bash
# Download (check for latest version at https://www.terraform.io/downloads)
TERRAFORM_VERSION="1.9.0"
wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Unzip and install
unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Verify
terraform --version
```

---

## tflint (Terraform Linter)

### Ubuntu/Debian

```bash
# Create local bin directory
mkdir -p ~/.local/bin

# Download latest version
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# Move to local bin
mv ./tflint ~/.local/bin/

# Add to PATH (add this to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc

# Verify installation
tflint --version
```

### Alternative: Download specific version

```bash
# Set version
TFLINT_VERSION="v0.50.3"

# Download
wget https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip

# Unzip and install
unzip -o tflint_linux_amd64.zip
mkdir -p ~/.local/bin
mv tflint ~/.local/bin/
rm tflint_linux_amd64.zip

# Verify
tflint --version
```

---

## Verification

After installing all tools, verify everything is working:

```bash
# Check all versions
echo "=== Python ==="
python3 --version

echo "=== Git ==="
git --version

echo "=== uv ==="
uv --version

echo "=== Pyright ==="
pyright --version

echo "=== Ruff ==="
ruff --version

echo "=== Make ==="
make --version | head -1

echo "=== Docker ==="
docker --version
docker compose version

echo "=== AWS CLI ==="
aws --version

echo "=== Terraform ==="
terraform --version | head -1

echo "=== tflint ==="
tflint --version
```

### Expected output example

```
=== Python ===
Python 3.11.x

=== Git ===
git version 2.x.x

=== uv ===
uv 0.x.x

=== Pyright ===
pyright 1.x.x

=== Ruff ===
ruff 0.x.x

=== Make ===
GNU Make 4.x

=== Docker ===
Docker version 24.x.x
Docker Compose version v2.x.x

=== AWS CLI ===
aws-cli/2.x.x

=== Terraform ===
Terraform v1.9.x

=== tflint ===
TFLint version 0.x.x
```

---

## Troubleshooting

### Command not found errors

If you get "command not found" after installation:

1. **Check PATH:**
   ```bash
   echo $PATH
   ```

2. **Add to PATH** (in ~/.bashrc or ~/.zshrc):
   ```bash
   export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
   ```

3. **Reload shell:**
   ```bash
   source ~/.bashrc  # or source ~/.zshrc
   ```

### Docker permission denied

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login, or run:
newgrp docker
```

### Python version conflicts

```bash
# Use python3.11 explicitly
python3.11 -m venv .venv

# Or set as default
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
```

### tflint not found in pre-commit

```bash
# Ensure tflint is in PATH
which tflint

# If not found, add to PATH in ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc
```

---

## Quick Start Script

Save this as `install-tools.sh` for automated installation:

```bash
#!/bin/bash
set -e

echo "Installing project dependencies..."

# Update system
sudo apt update

# Python
sudo apt install -y python3.11 python3.11-venv python3-pip

# Git
sudo apt install -y git

# Make
sudo apt install -y build-essential

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Node.js (for Pyright)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Pyright
sudo npm install -g pyright

# Ruff
~/.cargo/bin/uv tool install ruff

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
rm get-docker.sh

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform

# tflint
mkdir -p ~/.local/bin
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
mv ./tflint ~/.local/bin/

# Update PATH
echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> ~/.bashrc

echo "✅ Installation complete! Please logout/login or run: source ~/.bashrc"
```

---

## Next Steps

After installing all tools:

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd aws-base
   ```

2. **Set up pre-commit hooks:**
   ```bash
   make setup-pre-commit
   ```

3. **Install Python dependencies:**
   ```bash
   make uv-install
   ```

4. **Read the main README:**
   ```bash
   cat README.md
   ```

---

## Platform-Specific Notes

### macOS

Most tools can be installed via Homebrew:

```bash
# Install Homebrew first
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install python@3.11 git make docker aws-cli terraform tflint node uv ruff
brew install --cask docker

# Pyright
npm install -g pyright
```

### Windows (WSL2 recommended)

1. Install WSL2: https://learn.microsoft.com/en-us/windows/wsl/install
2. Install Ubuntu from Microsoft Store
3. Follow the Ubuntu/Debian instructions above

---

## Additional Resources

- [Python Documentation](https://docs.python.org/3/)
- [Git Documentation](https://git-scm.com/doc)
- [uv Documentation](https://github.com/astral-sh/uv)
- [Pyright Documentation](https://github.com/microsoft/pyright)
- [Ruff Documentation](https://docs.astral.sh/ruff/)
- [Docker Documentation](https://docs.docker.com/)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [tflint Documentation](https://github.com/terraform-linters/tflint)
