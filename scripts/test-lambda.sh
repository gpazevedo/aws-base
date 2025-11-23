#!/bin/bash
# =============================================================================
# Test Individual Lambda Service
# =============================================================================
# This script tests individual Lambda services by either:
# 1. Calling their Function URL (for HTTP services with direct access enabled)
# 2. Invoking them via AWS Lambda API (for event-driven services)
#
# Usage: ./scripts/test-lambda.sh SERVICE_NAME [ENVIRONMENT]
#
# Examples:
#   ./scripts/test-lambda.sh api
#   ./scripts/test-lambda.sh worker dev
#   ./scripts/test-lambda.sh scheduler prod
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
SERVICE_NAME="${1:-api}"
ENVIRONMENT="${2:-dev}"

# =============================================================================
# Validate Prerequisites
# =============================================================================

echo -e "${BLUE}🔍 Validating prerequisites...${NC}"

# Check if we're in the project root
if [ ! -d "terraform" ]; then
  echo -e "${RED}❌ Error: Must run from project root directory${NC}"
  echo "   Usage: ./scripts/test-lambda.sh SERVICE_NAME [ENVIRONMENT]"
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

# Try to get Function URL (for HTTP services with direct access)
SERVICE_URL=$(terraform output -raw lambda_${SERVICE_NAME}_url 2>/dev/null || echo "")

# Get function name (always available)
FUNCTION_NAME=$(terraform output -raw lambda_${SERVICE_NAME}_function_name 2>/dev/null || echo "")

if [ -z "$FUNCTION_NAME" ]; then
  echo -e "${RED}❌ Error: Service '${SERVICE_NAME}' not found in Terraform outputs${NC}"
  echo ""
  echo "Available Lambda services:"
  terraform output -json 2>/dev/null | jq -r 'keys[] | select(startswith("lambda_") and endswith("_function_name"))' | sed 's/lambda_//g' | sed 's/_function_name//g' || echo "  None found"
  echo ""
  echo "Make sure you have:"
  echo "  1. Created the service with: ./scripts/setup-terraform-lambda.sh ${SERVICE_NAME}"
  echo "  2. Deployed infrastructure with: make app-init-dev app-apply-dev"
  cd ..
  exit 1
fi

# Get log group name
LOG_GROUP=$(terraform output -raw lambda_${SERVICE_NAME}_log_group 2>/dev/null || echo "")

cd ..

echo -e "${GREEN}✅ Service configuration loaded${NC}"
echo "   Service: ${SERVICE_NAME}"
echo "   Function: ${FUNCTION_NAME}"
if [ -n "$SERVICE_URL" ] && [ "$SERVICE_URL" != "null" ]; then
  echo "   Function URL: ${SERVICE_URL}"
fi
if [ -n "$LOG_GROUP" ]; then
  echo "   Log Group: ${LOG_GROUP}"
fi
echo ""

# =============================================================================
# Test Service
# =============================================================================

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}         TESTING LAMBDA SERVICE: ${SERVICE_NAME}            ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"

if [ -n "$SERVICE_URL" ] && [ "$SERVICE_URL" != "null" ]; then
  # =============================================================================
  # Method 1: Test via Function URL (for HTTP services)
  # =============================================================================
  echo -e "${YELLOW}📡 Testing via Lambda Function URL...${NC}\n"

  # Test health endpoint
  echo -n "Testing /health endpoint... "
  if command -v jq &> /dev/null; then
    HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test-lambda-response.json "${SERVICE_URL}/health")
  else
    HTTP_CODE=$(curl -s -w "%{http_code}" "${SERVICE_URL}/health")
  fi

  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ PASS${NC} (HTTP $HTTP_CODE)"
    if command -v jq &> /dev/null && [ -f /tmp/test-lambda-response.json ]; then
      jq -C '.' /tmp/test-lambda-response.json 2>/dev/null || cat /tmp/test-lambda-response.json
    fi
  else
    echo -e "${RED}✗ FAIL${NC} (HTTP $HTTP_CODE)"
  fi
  echo ""

  # Test root endpoint
  echo -n "Testing / endpoint... "
  if command -v jq &> /dev/null; then
    HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test-lambda-response.json "${SERVICE_URL}/")
  else
    HTTP_CODE=$(curl -s -w "%{http_code}" "${SERVICE_URL}/")
  fi

  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ PASS${NC} (HTTP $HTTP_CODE)"
    if command -v jq &> /dev/null && [ -f /tmp/test-lambda-response.json ]; then
      jq -C '.' /tmp/test-lambda-response.json 2>/dev/null || cat /tmp/test-lambda-response.json
    fi
  else
    echo -e "${YELLOW}⚠ WARN${NC} (HTTP $HTTP_CODE)"
  fi
  echo ""

else
  # =============================================================================
  # Method 2: Test via AWS Lambda Invoke (for event-driven services)
  # =============================================================================
  echo -e "${YELLOW}⚡ Testing via AWS Lambda Invoke (no Function URL available)...${NC}\n"

  echo "Invoking Lambda function with test payload..."

  # Create test payload
  TEST_PAYLOAD='{"path":"/health","httpMethod":"GET"}'

  aws lambda invoke \
    --function-name "$FUNCTION_NAME" \
    --payload "$TEST_PAYLOAD" \
    /tmp/lambda-invoke-response.json

  echo ""
  echo -e "${BLUE}Response:${NC}"
  if command -v jq &> /dev/null; then
    jq -C '.' /tmp/lambda-invoke-response.json
  else
    cat /tmp/lambda-invoke-response.json
  fi
  echo ""
fi

# =============================================================================
# Show Recent Logs
# =============================================================================

if [ -n "$LOG_GROUP" ]; then
  echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}              RECENT CLOUDWATCH LOGS (last 5 min)            ${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"

  echo "Fetching recent logs from ${LOG_GROUP}..."
  aws logs tail "$LOG_GROUP" --since 5m --format short 2>/dev/null || echo "No recent logs or unable to fetch logs"
  echo ""
fi

# =============================================================================
# Test Summary
# =============================================================================

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                  ✓ TESTING COMPLETE!                       ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}📊 Service Information:${NC}"
echo "   Service: ${SERVICE_NAME}"
echo "   Function: ${FUNCTION_NAME}"
if [ -n "$SERVICE_URL" ] && [ "$SERVICE_URL" != "null" ]; then
  echo "   URL: ${SERVICE_URL}"
fi
echo ""

echo -e "${BLUE}📖 Next Steps:${NC}"
if [ -n "$SERVICE_URL" ] && [ "$SERVICE_URL" != "null" ]; then
  echo "   • View interactive API docs: ${SERVICE_URL}/docs"
  echo "   • Test custom endpoints: curl ${SERVICE_URL}/your-endpoint"
fi
echo "   • View logs: aws logs tail ${LOG_GROUP} --follow"
echo "   • Invoke directly: aws lambda invoke --function-name ${FUNCTION_NAME} --payload '{}' /tmp/response.json"
echo ""

# Cleanup
rm -f /tmp/test-lambda-response.json /tmp/lambda-invoke-response.json
