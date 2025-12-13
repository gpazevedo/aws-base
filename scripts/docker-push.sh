#!/bin/bash
# =============================================================================
# Build and Push Docker Image to ECR
# =============================================================================
# This script builds and pushes a Docker image to Amazon ECR with hierarchical tagging
# Usage: ./docker-push.sh [environment] [service] [dockerfile]
# Examples:
#   ./docker-push.sh dev api Dockerfile.lambda
#   ./docker-push.sh prod worker Dockerfile.lambda
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
ENVIRONMENT="${1:-dev}"
SERVICE="${2:-api}"
DOCKERFILE="${3:-}"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
  echo -e "${RED}❌ Error: Invalid environment '${ENVIRONMENT}'${NC}"
  echo "   Usage: $0 [dev|test|prod] [service] [dockerfile]"
  exit 1
fi

echo -e "${BLUE}🐳 Docker Build & Push Script${NC}"
echo "   Environment: ${ENVIRONMENT}"
echo "   Service: ${SERVICE}"
echo ""

# =============================================================================
# Detect CPU Architecture (target arch will be determined later after Dockerfile detection)
# =============================================================================
HOST_ARCH=$(uname -m)

# =============================================================================
# Read Bootstrap Configuration (or use environment variables)
# =============================================================================

# Check if required environment variables are set
if [ -z "$PROJECT_NAME" ] || [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
  echo -e "${BLUE}📖 Reading bootstrap outputs...${NC}"

  BOOTSTRAP_DIR="bootstrap"
  if [ ! -d "$BOOTSTRAP_DIR" ]; then
    echo -e "${RED}❌ Error: Bootstrap directory not found: $BOOTSTRAP_DIR${NC}"
    exit 1
  fi

  # Check if terraform.tfvars exists
  if [ ! -f "$BOOTSTRAP_DIR/terraform.tfvars" ]; then
    echo -e "${RED}❌ Error: Bootstrap configuration file not found: $BOOTSTRAP_DIR/terraform.tfvars${NC}"
    echo ""
    echo "   The bootstrap has not been configured yet."
    echo ""
    echo "   Please run:"
    echo "      cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars"
    echo ""
    echo "   Then edit bootstrap/terraform.tfvars and set:"
    echo "      - project_name"
    echo "      - github_org"
    echo "      - github_repo"
    echo "      - aws_region"
    echo "      - enable_lambda"
    echo ""
    echo "   After configuration, run:"
    echo "      make bootstrap-create bootstrap-init bootstrap-apply"
    echo ""
    exit 1
  fi

  # Check if Terraform has been initialized
  if [ ! -d "$BOOTSTRAP_DIR/.terraform" ]; then
    echo -e "${RED}❌ Error: Bootstrap Terraform not initialized${NC}"
    echo ""
    echo "   The bootstrap directory exists but Terraform has not been initialized."
    echo ""
    echo "   Please run:"
    echo "      make bootstrap-create bootstrap-init bootstrap-apply"
    echo ""
    exit 1
  fi

  cd "$BOOTSTRAP_DIR"

  # Get project name if not set
  if [ -z "$PROJECT_NAME" ]; then
    set +e  # Temporarily disable exit on error
    TF_OUTPUT=$(terraform output -raw project_name 2>&1)
    TF_EXIT_CODE=$?
    set -e  # Re-enable exit on error

    if [ $TF_EXIT_CODE -ne 0 ]; then
      echo -e "${RED}❌ Error: Could not read project_name from bootstrap${NC}"
      echo ""

      # Check if the error is about S3 bucket not existing
      if echo "$TF_OUTPUT" | grep -q "does not exist"; then
        echo "   The S3 bucket for Terraform state does not exist."
        echo "   This indicates bootstrap has not been created yet."
        echo ""
        echo "   Please run:"
        echo "      make bootstrap-create bootstrap-init bootstrap-apply"
      else
        echo "   Bootstrap Terraform state does not contain required outputs."
        echo "   This indicates bootstrap has not been applied yet."
        echo ""
        echo "   Please run:"
        echo "      make bootstrap-apply"
      fi
      echo ""
      cd ..
      exit 1
    fi

    PROJECT_NAME="$TF_OUTPUT"

    if [ -z "$PROJECT_NAME" ]; then
      echo -e "${RED}❌ Error: project_name is empty in bootstrap outputs${NC}"
      echo ""
      echo "   Please run:"
      echo "      make bootstrap-apply"
      echo ""
      cd ..
      exit 1
    fi
  fi

  # Get AWS account ID if not set
  if [ -z "$AWS_ACCOUNT_ID" ]; then
    set +e  # Temporarily disable exit on error
    TF_OUTPUT=$(terraform output -raw aws_account_id 2>&1)
    TF_EXIT_CODE=$?
    set -e  # Re-enable exit on error

    if [ $TF_EXIT_CODE -ne 0 ] || [ -z "$TF_OUTPUT" ]; then
      echo -e "${RED}❌ Error: Could not read aws_account_id from bootstrap${NC}"
      echo ""
      echo "   Bootstrap Terraform state does not contain required outputs."
      echo "   This indicates bootstrap has not been applied yet."
      echo ""
      echo "   Please run:"
      echo "      make bootstrap-apply"
      echo ""
      cd ..
      exit 1
    fi

    AWS_ACCOUNT_ID="$TF_OUTPUT"
  fi

  # Get AWS region if not set
  if [ -z "$AWS_REGION" ]; then
    set +e  # Temporarily disable exit on error
    AWS_REGION=$(terraform output -raw aws_region 2>&1)
    TF_EXIT_CODE=$?
    set -e  # Re-enable exit on error

    if [ $TF_EXIT_CODE -ne 0 ] || [ -z "$AWS_REGION" ]; then
      AWS_REGION="us-east-1"
      echo -e "${YELLOW}⚠️  Could not read aws_region from bootstrap, defaulting to: ${AWS_REGION}${NC}"
    fi
  fi

  cd ..

  # Verify bootstrap infrastructure exists in AWS
  echo -e "${BLUE}🔍 Verifying bootstrap deployment...${NC}"

  # Check S3 bucket for Terraform state
  BUCKET_NAME="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
  if ! aws s3 ls "s3://${BUCKET_NAME}" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: S3 bucket '${BUCKET_NAME}' not found in AWS${NC}"
    echo ""
    echo "   The Terraform state bucket does not exist in your AWS account."
    echo "   This indicates the bootstrap infrastructure has NOT been created."
    echo ""
    echo "   Please run:"
    echo "      make bootstrap-create"
    echo "      make bootstrap-init"
    echo "      make bootstrap-apply"
    echo ""
    exit 1
  fi
  echo -e "${GREEN}✅ S3 bucket verified: ${BUCKET_NAME}${NC}"

  # Check ECR repository
  if ! aws ecr describe-repositories --repository-names "${PROJECT_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: ECR repository '${PROJECT_NAME}' not found in AWS${NC}"
    echo ""
    echo "   Bootstrap configuration exists locally, but the ECR repository"
    echo "   was not found in your AWS account (region: ${AWS_REGION})."
    echo ""
    echo "   This indicates the bootstrap infrastructure has NOT been deployed."
    echo ""
    echo "   Please run:"
    echo "      make bootstrap-apply"
    echo ""
    exit 1
  fi
  echo -e "${GREEN}✅ ECR repository verified: ${PROJECT_NAME}${NC}"
  echo -e "${GREEN}✅ Bootstrap deployment verified${NC}"
else
  echo -e "${GREEN}✅ Using environment variables${NC}"
fi

# ECR repository is always the project name
ECR_REPOSITORY="${PROJECT_NAME}"

# Build ECR URL
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

echo -e "${GREEN}✅ Configuration:${NC}"
echo "   Project: ${PROJECT_NAME}"
echo "   ECR Repository: ${ECR_REPOSITORY}"
echo "   ECR URL: ${ECR_URL}"
echo "   AWS Account: ${AWS_ACCOUNT_ID}"
echo "   AWS Region: ${AWS_REGION}"
echo ""

# =============================================================================
# Validate Dockerfile and Service
# =============================================================================
if [ ! -d "backend/$SERVICE" ]; then
  echo -e "${RED}❌ Error: Service directory not found: backend/$SERVICE${NC}"
  echo ""
  echo "Available services:"
  ls -d backend/*/ 2>/dev/null | xargs -n1 basename || echo "  None found"
  exit 1
fi

# Auto-detect Dockerfile if not specified
if [ -z "$DOCKERFILE" ]; then
  echo -e "${BLUE}🔍 Auto-detecting Dockerfile...${NC}"

  # Check for common Dockerfile patterns in priority order
  if [ -f "backend/$SERVICE/Dockerfile.lambda" ]; then
    DOCKERFILE="Dockerfile.lambda"
  elif [ -f "backend/$SERVICE/Dockerfile.apprunner" ]; then
    DOCKERFILE="Dockerfile.apprunner"
  elif [ -f "backend/$SERVICE/Dockerfile" ]; then
    DOCKERFILE="Dockerfile"
  else
    echo -e "${RED}❌ Error: No Dockerfile found in backend/$SERVICE${NC}"
    echo ""
    echo "Available files:"
    ls -1 backend/$SERVICE/ 2>/dev/null || echo "  None found"
    echo ""
    echo "Please specify a Dockerfile explicitly:"
    echo "   Usage: $0 $ENVIRONMENT $SERVICE <dockerfile>"
    exit 1
  fi

  echo -e "${GREEN}✅ Found: ${DOCKERFILE}${NC}"
  echo ""
fi

# Strip any leading path from DOCKERFILE (user may have provided full path)
DOCKERFILE=$(basename "$DOCKERFILE")

# Validate the Dockerfile exists
if [ ! -f "backend/$SERVICE/$DOCKERFILE" ]; then
  echo -e "${RED}❌ Error: Dockerfile not found: backend/$SERVICE/$DOCKERFILE${NC}"
  echo ""
  echo "Available Dockerfiles in backend/$SERVICE:"
  ls -1 backend/$SERVICE/Dockerfile* 2>/dev/null || echo "  None found"
  echo ""
  echo "Usage: $0 [environment] [service] [dockerfile_name]"
  echo "   Note: Provide only the Dockerfile name, not the full path"
  echo "   Example: $0 dev api Dockerfile.lambda"
  exit 1
fi

echo "   Dockerfile: ${DOCKERFILE}"

# =============================================================================
# Determine Target Architecture based on Dockerfile
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

echo -e "${BLUE}🖥️  Architecture Detection${NC}"
echo "   Host CPU: ${HOST_ARCH}"
if [[ "$TARGET_ARCH" == "amd64" ]]; then
  echo "   Target: ${TARGET_ARCH} (AWS App Runner x86_64)"
else
  echo "   Target: ${TARGET_ARCH} (AWS Graviton2)"
fi
echo ""

# Check if we need QEMU (cross-platform build)
NEED_QEMU=false

# Normalize HOST_ARCH for comparison
if [[ "$HOST_ARCH" == "x86_64" ]]; then
  HOST_ARCH_NORMALIZED="amd64"
elif [[ "$HOST_ARCH" == "aarch64" ]]; then
  HOST_ARCH_NORMALIZED="arm64"
else
  HOST_ARCH_NORMALIZED="$HOST_ARCH"
fi

# Check if cross-platform build is needed
if [[ "$HOST_ARCH_NORMALIZED" != "$TARGET_ARCH" ]]; then
  NEED_QEMU=true
  echo -e "${YELLOW}⚠️  Cross-platform build detected (${HOST_ARCH_NORMALIZED} → ${TARGET_ARCH})${NC}"
  echo "   QEMU emulation required for ${TARGET_ARCH} builds"
  echo ""

  # Check if QEMU is already installed
  if docker buildx inspect --bootstrap 2>/dev/null | grep -q "linux/${TARGET_ARCH}"; then
    echo -e "${GREEN}✅ QEMU already installed and configured${NC}"
  else
    echo -e "${YELLOW}📦 Installing QEMU for cross-platform builds...${NC}"
    echo "   This is a one-time setup"
    echo ""

    # Install QEMU emulation
    docker run --privileged --rm tonistiigi/binfmt --install all

    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅ QEMU installed successfully${NC}"
    else
      echo -e "${RED}❌ Error: Failed to install QEMU${NC}"
      echo "   You can install it manually with:"
      echo "   docker run --privileged --rm tonistiigi/binfmt --install all"
      exit 1
    fi
  fi
  echo ""
else
  echo -e "${GREEN}✅ Native ${TARGET_ARCH} build - no emulation needed${NC}"
  echo ""
fi

# =============================================================================
# Login to ECR
# =============================================================================
echo -e "${BLUE}🔐 Logging into Amazon ECR...${NC}"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Failed to login to ECR${NC}"
  echo "   Please check your AWS credentials"
  exit 1
fi

echo -e "${GREEN}✅ Successfully logged into ECR${NC}"
echo ""

# =============================================================================
# Configure CodeArtifact (if needed by Dockerfile)
# =============================================================================
# Check if the Dockerfile uses CodeArtifact (has CODEARTIFACT_INDEX_URL arg)
USES_CODEARTIFACT=false
if grep -q "ARG CODEARTIFACT_INDEX_URL" "backend/${SERVICE}/${DOCKERFILE}"; then
  USES_CODEARTIFACT=true
  echo -e "${BLUE}🔐 Configuring CodeArtifact authentication...${NC}"

  DOMAIN="${CODEARTIFACT_DOMAIN:-agsys}"
  # Use agsys-common as the default repository (shared across projects)
  # Can be overridden with CODEARTIFACT_REPOSITORY environment variable
  REPOSITORY="${CODEARTIFACT_REPOSITORY:-${DOMAIN}-common}"

  # Get CodeArtifact token
  CODEARTIFACT_TOKEN=$(aws codeartifact get-authorization-token \
    --domain "$DOMAIN" \
    --domain-owner "$AWS_ACCOUNT_ID" \
    --query authorizationToken \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

  if [ -z "$CODEARTIFACT_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  CodeArtifact authentication failed. Domain '$DOMAIN' may not exist.${NC}"
    echo "   If this service doesn't use agsys-common, this is OK."
    USES_CODEARTIFACT=false
  else
    # Get repository endpoint
    CODEARTIFACT_ENDPOINT=$(aws codeartifact get-repository-endpoint \
      --domain "$DOMAIN" \
      --domain-owner "$AWS_ACCOUNT_ID" \
      --repository "$REPOSITORY" \
      --format pypi \
      --query repositoryEndpoint \
      --output text \
      --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -z "$CODEARTIFACT_ENDPOINT" ]; then
      echo -e "${RED}❌ Error: Failed to get CodeArtifact endpoint${NC}"
      echo "   Repository: $REPOSITORY"
      exit 1
    fi

    CODEARTIFACT_INDEX_URL="https://aws:${CODEARTIFACT_TOKEN}@${CODEARTIFACT_ENDPOINT#https://}simple/"
    echo -e "${GREEN}✅ CodeArtifact configured${NC}"
    echo "   Domain: ${DOMAIN}"
    echo "   Repository: ${REPOSITORY}"
    echo ""
  fi
fi

# =============================================================================
# Build Docker Image
# =============================================================================
echo -e "${BLUE}🏗️  Building Docker image for ${TARGET_ARCH}...${NC}"

# Generate timestamp and git SHA
TIMESTAMP=$(date -u +%Y-%m-%d-%H-%M)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")

# Hierarchical tag format: service-environment-datetime-sha
# Note: Using hyphens instead of slashes (Docker tags cannot contain /)
PRIMARY_TAG="${SERVICE}-${ENVIRONMENT}-${TIMESTAMP}-${GIT_SHA}"
SERVICE_LATEST_TAG="${SERVICE}-${ENVIRONMENT}-latest"
ENV_LATEST_TAG="${ENVIRONMENT}-latest"

echo "   Service folder: backend/${SERVICE}"
echo "   Dockerfile: backend/${SERVICE}/${DOCKERFILE}"
echo "   Target architecture: ${TARGET_ARCH}"
echo "   Primary tag: ${PRIMARY_TAG}"
if [ "$USES_CODEARTIFACT" = true ]; then
  echo "   CodeArtifact: enabled"
fi
echo ""

# Build command with optional CodeArtifact args
BUILD_ARGS=""
if [ "$USES_CODEARTIFACT" = true ]; then
  BUILD_ARGS="--build-arg CODEARTIFACT_INDEX_URL=${CODEARTIFACT_INDEX_URL} --build-arg UV_EXTRA_INDEX_URL=https://pypi.org/simple/"
fi

# Use buildx for reliable cross-platform builds
docker buildx build \
  --platform=linux/${TARGET_ARCH} \
  -f "backend/${SERVICE}/${DOCKERFILE}" \
  -t "${ECR_URL}:${PRIMARY_TAG}" \
  -t "${ECR_URL}:${SERVICE_LATEST_TAG}" \
  -t "${ECR_URL}:${ENV_LATEST_TAG}" \
  ${BUILD_ARGS} \
  --load \
  .

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Docker build failed${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Docker image built successfully${NC}"
echo ""

# =============================================================================
# Push to ECR
# =============================================================================
echo -e "${BLUE}📤 Pushing images to ECR...${NC}"
echo ""

echo "   Pushing: ${PRIMARY_TAG}"
docker push "${ECR_URL}:${PRIMARY_TAG}"

echo "   Pushing: ${SERVICE_LATEST_TAG}"
docker push "${ECR_URL}:${SERVICE_LATEST_TAG}"

echo "   Pushing: ${ENV_LATEST_TAG}"
docker push "${ECR_URL}:${ENV_LATEST_TAG}"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error: Failed to push to ECR${NC}"
  exit 1
fi

# -----------------------------------------------------------------------------
# After image is pushed (write the created tag into Terraform files so the
# lambda/app-runner TF uses the pushed image)
# -----------------------------------------------------------------------------
TF_DIR="terraform"
LAMBDA_TF_FILE="$TF_DIR/lambda-${SERVICE}.tf"
APPRUNNER_TF_FILE="$TF_DIR/apprunner-${SERVICE}.tf"

# Determine ECR repository URI. Prefer explicit ECR_REPOSITORY_URI env var,
# otherwise try to query AWS ECR for repository named for the service.
if [ -n "${ECR_REPOSITORY_URI:-}" ]; then
  ECR_URI="$ECR_REPOSITORY_URI"
else
  REPO_NAME="${ECR_REPOSITORY:-${SERVICE}}"
  ECR_URI="$(aws ecr describe-repositories --repository-names "$REPO_NAME" --query 'repositories[0].repositoryUri' --output text 2>/dev/null || true)"
fi

if [ -z "$ECR_URI" ]; then
  echo "❌ Could not determine ECR repository URI. Set ECR_REPOSITORY_URI or ensure repository exists."
  exit 1
fi

IMAGE_URI="${ECR_URI}:${PRIMARY_TAG}"

# # Tag & push (ensure docker image exists locally as $LOCAL_IMAGE)
# docker tag "${LOCAL_IMAGE:-${SERVICE}:latest}" "${IMAGE_URI}"
# docker push "${IMAGE_URI}"

# Update lambda-*.tf image_uri if file exists
if [ -f "$LAMBDA_TF_FILE" ]; then
  sed -i "s|^[[:space:]]*image_uri[[:space:]]*=.*$|  image_uri    = \"${IMAGE_URI}\"|" "$LAMBDA_TF_FILE" || true
  echo "✅ Wrote image_uri = ${IMAGE_URI} to ${LAMBDA_TF_FILE}"
fi

# Update apprunner-*.tf image_identifier if file exists
if [ -f "$APPRUNNER_TF_FILE" ]; then
  sed -i "s|^[[:space:]]*image_identifier[[:space:]]*=.*$|  image_identifier = \"${IMAGE_URI}\"|" "$APPRUNNER_TF_FILE" || true
  echo "✅ Wrote image_identifier = ${IMAGE_URI} to ${APPRUNNER_TF_FILE}"
fi
# =============================================================================

echo ""
echo -e "${GREEN}✅ Successfully pushed images to ECR!${NC}"
echo ""
echo -e "${BLUE}📋 Image URIs (${TARGET_ARCH} architecture):${NC}"
echo "   ${ECR_URL}:${PRIMARY_TAG}"
echo "   ${ECR_URL}:${SERVICE_LATEST_TAG}"
echo "   ${ECR_URL}:${ENV_LATEST_TAG}"
echo ""
echo -e "${BLUE}📊 Image Details:${NC}"
echo "   Repository: ${ECR_REPOSITORY}"
echo "   Service: ${SERVICE}"
echo "   Environment: ${ENVIRONMENT}"
echo "   Git SHA: ${GIT_SHA}"
echo "   Timestamp: ${TIMESTAMP}"
echo "   Architecture: ${TARGET_ARCH}"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo "   1. Verify images in ECR:"
echo "      aws ecr describe-images --repository-name ${ECR_REPOSITORY} --query 'reverse(sort_by(imageDetails[?imageTags[?contains(@, \`${SERVICE}-${ENVIRONMENT}\`)]], &imagePushedAt))[0]' --output json"
echo ""
echo "   2. Deploy with Terraform:"
echo "      make app-init-dev app-apply-dev"
echo ""
