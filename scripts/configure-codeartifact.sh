#!/bin/bash
# =============================================================================
# Configure CodeArtifact Authentication
# =============================================================================
# This script configures pip and uv to authenticate with AWS CodeArtifact.
# The authentication token is valid for 12 hours.
#
# Usage:
#   source <(./scripts/configure-codeartifact.sh)
#
# This will set environment variables for pip and uv to use CodeArtifact.
# =============================================================================

set -euo pipefail

# Configuration
DOMAIN="${CODEARTIFACT_DOMAIN:-agsys}"
PROJECT_NAME="${PROJECT_NAME:-common}"
# Pattern 2: Project-specific repository (domain-project)
# Override with CODEARTIFACT_REPOSITORY if you need a different repository
REPOSITORY="${CODEARTIFACT_REPOSITORY:-${DOMAIN}-${PROJECT_NAME}}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}" >&2
    echo "Install it with: pip install awscli" >&2
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}" >&2
    echo "Configure AWS credentials first" >&2
    exit 1
fi

echo -e "${BLUE}Configuring CodeArtifact authentication...${NC}" >&2

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get authentication token (valid for 12 hours)
TOKEN=$(aws codeartifact get-authorization-token \
    --domain "$DOMAIN" \
    --domain-owner "$ACCOUNT_ID" \
    --query authorizationToken \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Failed to get CodeArtifact authentication token${NC}" >&2
    echo "Make sure the domain '$DOMAIN' exists and you have access" >&2
    exit 1
fi

# Get repository endpoint
ENDPOINT=$(aws codeartifact get-repository-endpoint \
    --domain "$DOMAIN" \
    --domain-owner "$ACCOUNT_ID" \
    --repository "$REPOSITORY" \
    --format pypi \
    --query repositoryEndpoint \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ -z "$ENDPOINT" ]; then
    echo -e "${RED}Error: Failed to get repository endpoint${NC}" >&2
    echo "Make sure the repository '$REPOSITORY' exists" >&2
    exit 1
fi

# Construct authenticated index URL
INDEX_URL="https://aws:${TOKEN}@${ENDPOINT#https://}simple/"

# Output environment variable exports
cat << EOF
# CodeArtifact configuration (token expires in 12 hours)
# Domain: ${DOMAIN}
# Repository: ${REPOSITORY}
# Region: ${AWS_REGION}

# pip configuration
export PIP_INDEX_URL='${INDEX_URL}'
export PIP_EXTRA_INDEX_URL='https://pypi.org/simple/'

# uv configuration
export UV_INDEX_URL='${INDEX_URL}'
export UV_EXTRA_INDEX_URL='https://pypi.org/simple/'

# Store configuration for scripts
export CODEARTIFACT_DOMAIN='${DOMAIN}'
export CODEARTIFACT_REPOSITORY='${REPOSITORY}'
export CODEARTIFACT_INDEX_URL='${INDEX_URL}'
export CODEARTIFACT_ENDPOINT='${ENDPOINT}'

EOF

echo -e "${GREEN}✓ CodeArtifact configured successfully${NC}" >&2
echo -e "${YELLOW}Token valid for 12 hours${NC}" >&2
