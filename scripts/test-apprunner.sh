#!/bin/bash
# =============================================================================
# Test Individual App Runner Service
# =============================================================================
# This script tests individual App Runner services by calling their service URLs
#
# Usage: ./scripts/test-apprunner.sh SERVICE_NAME [ENVIRONMENT]
#
# Examples:
#   ./scripts/test-apprunner.sh web
#   ./scripts/test-apprunner.sh admin dev
#   ./scripts/test-apprunner.sh dashboard prod
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SERVICE_NAME="${1:-apprunner}"
ENVIRONMENT="${2:-dev}"

# =============================================================================
# Validate Prerequisites
# =============================================================================

echo -e "${BLUE}🔍 Validating prerequisites...${NC}"

# Check if we're in the project root
if [ ! -d "terraform" ]; then
  echo -e "${RED}❌ Error: Must run from project root directory${NC}"
  echo "   Usage: ./scripts/test-apprunner.sh SERVICE_NAME [ENVIRONMENT]"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${YELLOW}⚠️  Warning: jq is not installed (JSON output will not be pretty-printed)${NC}"
  echo "   Install with: sudo apt-get install jq (Ubuntu/Debian)"
  echo "              or: brew install jq (macOS)"
fi

echo -e "${GREEN}✅ Prerequisites validated${NC}\n"

# =============================================================================
# Get Service Configuration
# =============================================================================

echo -e "${BLUE}📖 Reading Terraform outputs for service '${SERVICE_NAME}'...${NC}"

cd terraform

# Try to get Service URL (should always be available for App Runner)
SERVICE_URL=$(terraform output -raw apprunner_${SERVICE_NAME}_url 2>/dev/null || echo "")

# Get service status
SERVICE_STATUS=$(terraform output -raw apprunner_${SERVICE_NAME}_status 2>/dev/null || echo "")

# Get service ARN
SERVICE_ARN=$(terraform output -raw apprunner_${SERVICE_NAME}_arn 2>/dev/null || echo "")

if [ -z "$SERVICE_URL" ]; then
  echo -e "${RED}❌ Error: Service '${SERVICE_NAME}' not found in Terraform outputs${NC}"
  echo ""
  echo "Available App Runner services:"
  terraform output -json 2>/dev/null | jq -r 'keys[] | select(startswith("apprunner_") and endswith("_url"))' | sed 's/apprunner_//g' | sed 's/_url//g' || echo "  None found"
  echo ""
  echo "Make sure you have:"
  echo "  1. Created the service with: ./scripts/setup-terraform-apprunner.sh ${SERVICE_NAME}"
  echo "  2. Deployed infrastructure with: make app-init-dev app-apply-dev"
  cd ..
  exit 1
fi

cd ..

echo -e "${GREEN}✅ Service configuration loaded${NC}"
echo "   Service: ${SERVICE_NAME}"
echo "   URL: ${SERVICE_URL}"
if [ -n "$SERVICE_STATUS" ]; then
  echo "   Status: ${SERVICE_STATUS}"
fi
if [ -n "$SERVICE_ARN" ]; then
  echo "   ARN: ${SERVICE_ARN}"
fi
echo ""

# =============================================================================
# Test Service
# =============================================================================

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}      TESTING APP RUNNER SERVICE: ${SERVICE_NAME}            ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"

# Test health endpoint
echo -n "Testing /health endpoint... "
if command -v jq &> /dev/null; then
  HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test-apprunner-response.json "${SERVICE_URL}/health")
else
  HTTP_CODE=$(curl -s -w "%{http_code}" "${SERVICE_URL}/health")
fi

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS${NC} (HTTP $HTTP_CODE)"
  if command -v jq &> /dev/null && [ -f /tmp/test-apprunner-response.json ]; then
    jq -C '.' /tmp/test-apprunner-response.json 2>/dev/null || cat /tmp/test-apprunner-response.json
  fi
else
  echo -e "${RED}✗ FAIL${NC} (HTTP $HTTP_CODE)"
fi
echo ""

# Test root endpoint
echo -n "Testing / endpoint... "
if command -v jq &> /dev/null; then
  HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test-apprunner-response.json "${SERVICE_URL}/")
else
  HTTP_CODE=$(curl -s -w "%{http_code}" "${SERVICE_URL}/")
fi

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS${NC} (HTTP $HTTP_CODE)"
  if command -v jq &> /dev/null && [ -f /tmp/test-apprunner-response.json ]; then
    jq -C '.' /tmp/test-apprunner-response.json 2>/dev/null || cat /tmp/test-apprunner-response.json
  fi
else
  echo -e "${YELLOW}⚠ WARN${NC} (HTTP $HTTP_CODE)"
fi
echo ""

# Test docs endpoint (if available)
echo -n "Testing /docs endpoint... "
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null "${SERVICE_URL}/docs")

if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS${NC} (HTTP $HTTP_CODE)"
  echo "   OpenAPI docs available at: ${SERVICE_URL}/docs"
elif [ "$HTTP_CODE" = "404" ]; then
  echo -e "${YELLOW}⚠ SKIP${NC} (Not available)"
else
  echo -e "${YELLOW}⚠ WARN${NC} (HTTP $HTTP_CODE)"
fi
echo ""

# =============================================================================
# Test Summary
# =============================================================================

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                  ✓ TESTING COMPLETE!                       ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}📊 Service Information:${NC}"
echo "   Service: ${SERVICE_NAME}"
echo "   URL: ${SERVICE_URL}"
if [ -n "$SERVICE_STATUS" ]; then
  echo "   Status: ${SERVICE_STATUS}"
fi
echo ""

echo -e "${BLUE}📖 Next Steps:${NC}"
echo "   • View interactive API docs: ${SERVICE_URL}/docs"
echo "   • View alternative docs: ${SERVICE_URL}/redoc"
echo "   • Test custom endpoints: curl ${SERVICE_URL}/your-endpoint"
echo "   • View logs in AWS Console: App Runner > ${SERVICE_NAME} > Logs"
echo ""

# Cleanup
rm -f /tmp/test-apprunner-response.json
