#!/bin/bash
# =============================================================================
# Publish agsys-common Library to AWS CodeArtifact
# =============================================================================
# This script publishes the built agsys-common package to AWS CodeArtifact.
# It handles authentication and uses twine to upload the package.
#
# Prerequisites:
#   - Package must be built first (run ./scripts/build-common-library.sh)
#   - AWS credentials must be configured
#   - CodeArtifact domain and repository must exist
#
# Usage:
#   ./scripts/publish-common-library.sh
#
# Environment Variables:
#   CODEARTIFACT_DOMAIN    - CodeArtifact domain (default: agsys)
#   PROJECT_NAME           - Project name (default: common)
#   CODEARTIFACT_REPOSITORY - Repository name (default: {domain}-{project})
#   AWS_REGION             - AWS region (default: us-east-1)
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="${CODEARTIFACT_DOMAIN:-agsys}"
PROJECT_NAME="${PROJECT_NAME:-common}"
# Pattern 2: Project-specific repository (domain-project)
# Override with CODEARTIFACT_REPOSITORY if you need a different repository
REPOSITORY="${CODEARTIFACT_REPOSITORY:-${DOMAIN}-${PROJECT_NAME}}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo -e "${BLUE}Publishing agsys-common library to AWS CodeArtifact...${NC}"
echo -e "${BLUE}Domain: ${DOMAIN}${NC}"
echo -e "${BLUE}Repository: ${REPOSITORY}${NC}"
echo -e "${BLUE}Region: ${AWS_REGION}${NC}"
echo ""

# Check if package is built
if [ ! -d "agsys/common/dist" ] || [ -z "$(ls -A agsys/common/dist 2>/dev/null)" ]; then
    echo -e "${YELLOW}Package not built. Running build first...${NC}"
    ./scripts/build-common-library.sh
    echo ""
fi

cd agsys/common

# Get package version
VERSION=$(grep '^version = ' pyproject.toml | cut -d'"' -f2)
echo -e "${BLUE}Publishing version: ${VERSION}${NC}"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get CodeArtifact authentication token
echo -e "${BLUE}Getting CodeArtifact authentication token...${NC}"
export TWINE_USERNAME=aws
export TWINE_PASSWORD=$(aws codeartifact get-authorization-token \
    --domain "$DOMAIN" \
    --domain-owner "$ACCOUNT_ID" \
    --region "$AWS_REGION" \
    --query authorizationToken \
    --output text)

if [ -z "$TWINE_PASSWORD" ]; then
    echo -e "${RED}Error: Failed to get authentication token${NC}"
    echo "Make sure the domain '$DOMAIN' exists and you have publish permissions"
    exit 1
fi

# Get repository endpoint
REPO_ENDPOINT=$(aws codeartifact get-repository-endpoint \
    --domain "$DOMAIN" \
    --domain-owner "$ACCOUNT_ID" \
    --repository "$REPOSITORY" \
    --format pypi \
    --region "$AWS_REGION" \
    --query repositoryEndpoint \
    --output text)

if [ -z "$REPO_ENDPOINT" ]; then
    echo -e "${RED}Error: Failed to get repository endpoint${NC}"
    echo "Make sure the repository '$REPOSITORY' exists"
    exit 1
fi

export TWINE_REPOSITORY_URL="${REPO_ENDPOINT}"

# Install twine if not available
echo -e "${BLUE}Ensuring twine is installed...${NC}"
uv tool install twine --quiet 2>/dev/null || uv tool upgrade twine --quiet 2>/dev/null || true

# Upload to CodeArtifact
echo -e "${BLUE}Uploading package to CodeArtifact...${NC}"
uvx twine upload --repository-url "$TWINE_REPOSITORY_URL" dist/*

echo ""
echo -e "${GREEN}✓ Package published successfully to CodeArtifact${NC}"
echo -e "${GREEN}Package: agsys-common ${VERSION}${NC}"
echo -e "${GREEN}Domain: ${DOMAIN}${NC}"
echo -e "${GREEN}Repository: ${REPOSITORY}${NC}"
echo -e "${GREEN}Region: ${AWS_REGION}${NC}"

# List package versions to verify
echo ""
echo -e "${BLUE}Verifying package versions in repository:${NC}"
aws codeartifact list-package-versions \
    --domain "$DOMAIN" \
    --domain-owner "$ACCOUNT_ID" \
    --repository "$REPOSITORY" \
    --format pypi \
    --package agsys-common \
    --region "$AWS_REGION" \
    --query 'versions[*].[version,status]' \
    --output table || echo -e "${YELLOW}Note: Package listing may take a moment to update${NC}"

echo ""
echo -e "${GREEN}Publication complete!${NC}"
echo -e "Install with: ${YELLOW}uv add \"agsys-common>=${VERSION}\"${NC}"
