#!/bin/bash
# =============================================================================
# Test API Endpoints
# =============================================================================
# This script tests all API endpoints after deployment to verify functionality.
# It automatically detects API Keys if enabled and tests with proper headers.
#
# Usage: ./scripts/test-api.sh
#
# Requirements:
# - Terraform outputs must be available (run from project root)
# - jq must be installed for JSON parsing
# - curl must be installed
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Validate Prerequisites
# =============================================================================

echo -e "${BLUE}🔍 Validating prerequisites...${NC}"

# Check if we're in the project root
if [ ! -d "terraform" ]; then
  echo -e "${RED}❌ Error: Must run from project root directory${NC}"
  echo "   Usage: ./scripts/test-api.sh"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ Error: jq is not installed${NC}"
  echo "   Install with: sudo apt-get install jq (Ubuntu/Debian)"
  echo "              or: brew install jq (macOS)"
  exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
  echo -e "${RED}❌ Error: curl is not installed${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Prerequisites validated${NC}\n"

# =============================================================================
# Get API Configuration
# =============================================================================

echo -e "${BLUE}📖 Reading Terraform outputs...${NC}"

cd terraform

# Get API URL
if ! PRIMARY_URL=$(terraform output -raw primary_endpoint 2>/dev/null); then
  echo -e "${RED}❌ Error: Could not read primary_endpoint from Terraform outputs${NC}"
  echo "   Make sure you have deployed the infrastructure:"
  echo "   1. make app-init-dev"
  echo "   2. make app-apply-dev"
  exit 1
fi

# Get API Key if enabled
API_KEY=$(terraform output -raw api_key_value 2>/dev/null || echo "")

# Get deployment mode
DEPLOYMENT_MODE=$(terraform output -raw deployment_mode 2>/dev/null || echo "unknown")

cd ..

echo -e "${GREEN}✅ Configuration loaded${NC}"
echo "   API URL: ${PRIMARY_URL}"
echo "   Deployment Mode: ${DEPLOYMENT_MODE}"
if [ -n "$API_KEY" ]; then
  echo "   API Key: Enabled (will be used in requests)"
else
  echo "   API Key: Disabled"
fi
echo ""

# =============================================================================
# Test Endpoint Function
# =============================================================================

test_endpoint() {
  local method=$1
  local path=$2
  local expected_status=$3
  local data=$4
  local description=$5

  echo -n "Testing: $description... "

  # Build curl command
  local cmd="curl -s -w '%{http_code}' -o /tmp/test-api-response.json"

  # Add API Key header if available
  if [ -n "$API_KEY" ]; then
    cmd="$cmd -H 'x-api-key: $API_KEY'"
  fi

  # Add method
  cmd="$cmd -X $method"

  # Add data if provided
  if [ -n "$data" ]; then
    cmd="$cmd -H 'Content-Type: application/json' -d '$data'"
  fi

  # Add URL
  cmd="$cmd $PRIMARY_URL$path"

  # Execute request
  status_code=$(eval $cmd)

  # Check status code
  if [ "$status_code" = "$expected_status" ]; then
    echo -e "${GREEN}✓ PASS${NC} (HTTP $status_code)"

    # Pretty print JSON response
    if jq -e . /tmp/test-api-response.json >/dev/null 2>&1; then
      jq -C '.' /tmp/test-api-response.json
    else
      cat /tmp/test-api-response.json
    fi
  else
    echo -e "${RED}✗ FAIL${NC} (Expected HTTP $expected_status, got HTTP $status_code)"
    echo -e "${RED}Response:${NC}"
    cat /tmp/test-api-response.json
    echo ""
    exit 1
  fi
  echo ""
}

# =============================================================================
# Run Tests
# =============================================================================

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    API ENDPOINT TESTS                      ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"

# Health Check Endpoints
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Health Check Endpoints${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

test_endpoint "GET" "/health" "200" "" "Health check endpoint"
test_endpoint "GET" "/liveness" "200" "" "Liveness probe"
test_endpoint "GET" "/readiness" "200" "" "Readiness probe"

# Application Endpoints
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Application Endpoints${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

test_endpoint "GET" "/" "200" "" "Root endpoint"
test_endpoint "GET" "/greet" "200" "" "Greet with default name"
test_endpoint "GET" "/greet?name=Alice" "200" "" "Greet with query parameter"
test_endpoint "POST" "/greet" "200" '{"name":"Bob"}' "Greet with POST body"

# Error Handling
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Error Handling${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

test_endpoint "GET" "/error" "500" "" "Error endpoint (test error handling)"
test_endpoint "POST" "/greet" "422" '{}' "Validation error (missing required field)"

# =============================================================================
# Test Summary
# =============================================================================

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                  ✓ ALL TESTS PASSED!                       ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}📊 Test Summary:${NC}"
echo "   • Health checks: 3/3 passed"
echo "   • Application endpoints: 4/4 passed"
echo "   • Error handling: 2/2 passed"
echo "   • Total: 9/9 tests passed"
echo ""

echo -e "${BLUE}📖 Next Steps:${NC}"
echo "   • View interactive API docs: ${PRIMARY_URL}/docs"
echo "   • View alternative docs: ${PRIMARY_URL}/redoc"
echo "   • Download OpenAPI schema: curl ${PRIMARY_URL}/openapi.json"
echo ""

# Cleanup
rm -f /tmp/test-api-response.json
