#!/usr/bin/env bash
# =============================================================================
# Health Check Test Script for Multi-Service AWS Infrastructure
# =============================================================================
# Tests health check endpoints for deployed services (Lambda + AppRunner)
# via API Gateway or direct URLs
#
# Auto-discovers deployed services from Terraform outputs
#
# Usage:
#   ./scripts/test-health.sh [ENVIRONMENT] [PROJECT_NAME] [SERVICE]
#
# Arguments:
#   ENVIRONMENT  - Environment to test (dev, test, prod). Default: dev
#   PROJECT_NAME - Project name (auto-detected if not provided)
#   SERVICE      - Specific service to test or "all". Default: auto-discover all deployed services
#
# Examples:
#   ./scripts/test-health.sh                    # Auto-discover and test all services in dev
#   ./scripts/test-health.sh prod               # Auto-discover and test all services in prod
#   ./scripts/test-health.sh dev fingus         # Auto-discover and test all services
#   ./scripts/test-health.sh dev fingus api     # Test only API service
# =============================================================================

set -euo pipefail

# Ensure script executes from project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# =============================================================================
# Configuration
# =============================================================================

# Environment, project name, and service from arguments or defaults
ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${2:-}"
SERVICE_FILTER="${3:-}"

# Auto-detect project name from terraform.tfvars if not provided
if [ -z "$PROJECT_NAME" ]; then
    if [ -f "terraform/environments/${ENVIRONMENT}.tfvars" ]; then
        PROJECT_NAME=$(grep '^project_name' "terraform/environments/${ENVIRONMENT}.tfvars" | cut -d'=' -f2 | tr -d ' "' | head -n1)
    fi

    # Fallback to bootstrap if still not found
    if [ -z "$PROJECT_NAME" ] && [ -f "bootstrap/terraform.tfvars" ]; then
        PROJECT_NAME=$(grep '^project_name' "bootstrap/terraform.tfvars" | cut -d'=' -f2 | tr -d ' "' | head -n1)
    fi

    # Final fallback
    PROJECT_NAME="${PROJECT_NAME:-myproject}"
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Health Check Test - Multi-Service Infrastructure       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Environment:${NC} $ENVIRONMENT"
echo -e "${BLUE}Project:${NC}     $PROJECT_NAME"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
    echo -e "${RED}❌ Error: Invalid environment. Must be 'dev', 'test', or 'prod'${NC}"
    exit 1
fi

# =============================================================================
# Retrieve Infrastructure URLs from Terraform
# =============================================================================

echo ""
echo -e "${BLUE}🔍 Discovering deployed services from Terraform...${NC}"

cd terraform 2>/dev/null || {
    echo -e "${RED}❌ Error: terraform directory not found${NC}"
    echo "   Make sure you are in the project root directory"
    exit 1
}

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo -e "${RED}❌ Error: Terraform not initialized${NC}"
    echo "   Run: cd terraform && terraform init -backend-config=environments/${ENVIRONMENT}-backend.hcl"
    exit 1
fi

# Get all Terraform outputs
ALL_OUTPUTS=$(terraform output -json 2>/dev/null || echo "{}")

# Get API Gateway URL (primary endpoint)
API_GATEWAY_URL=$(echo "$ALL_OUTPUTS" | jq -r '.api_gateway_url.value // ""' 2>/dev/null || echo "")

# Get deployment mode
DEPLOYMENT_MODE=$(echo "$ALL_OUTPUTS" | jq -r '.deployment_mode.value // "unknown"' 2>/dev/null || echo "unknown")

# Auto-discover Lambda services from outputs
# Also detect which Lambda services use root path (typically 'api') vs path prefix
declare -A LAMBDA_SERVICES_MAP
for output in $(echo "$ALL_OUTPUTS" | jq -r 'keys[]' 2>/dev/null); do
    if [[ "$output" =~ ^lambda_([a-z0-9_-]+)_function_name$ ]]; then
        service_name="${BASH_REMATCH[1]}"
        # By default, assume services use their name as path prefix
        # The 'api' service is special - it typically uses root path (/)
        LAMBDA_SERVICES_MAP["$service_name"]="$service_name"
    fi
done

# Auto-discover AppRunner services from outputs
declare -A APPRUNNER_SERVICES_MAP
for output in $(echo "$ALL_OUTPUTS" | jq -r 'keys[]' 2>/dev/null); do
    if [[ "$output" =~ ^apprunner_([a-z0-9_-]+)_url$ ]]; then
        service_name="${BASH_REMATCH[1]}"
        # AppRunner services always use their name as path prefix
        APPRUNNER_SERVICES_MAP["$service_name"]="$service_name"
    fi
done

# Combine all discovered services
LAMBDA_SERVICES=("${!LAMBDA_SERVICES_MAP[@]}")
APPRUNNER_SERVICES=("${!APPRUNNER_SERVICES_MAP[@]}")
ALL_SERVICES=("${LAMBDA_SERVICES[@]}" "${APPRUNNER_SERVICES[@]}")

# Return to project root
cd "$PROJECT_ROOT"

# Display discovered services
if [ ${#ALL_SERVICES[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No services discovered${NC}"
    echo "   Make sure infrastructure is deployed"
    exit 1
fi

echo -e "${GREEN}✅ Discovered services:${NC}"
for svc in "${ALL_SERVICES[@]}"; do
    if [[ " ${LAMBDA_SERVICES[@]} " =~ " ${svc} " ]]; then
        # Determine path prefix for Lambda service
        if [ "$svc" = "api" ]; then
            echo -e "   - ${svc} (Lambda) - Root path (/)"
        else
            echo -e "   - ${svc} (Lambda) - Path prefix (/${svc})"
        fi
    elif [[ " ${APPRUNNER_SERVICES[@]} " =~ " ${svc} " ]]; then
        echo -e "   - ${svc} (AppRunner) - Path prefix (/${svc})"
    fi
done

# Determine which services to test
SERVICES_TO_TEST=()
if [ -z "$SERVICE_FILTER" ] || [ "$SERVICE_FILTER" = "all" ]; then
    SERVICES_TO_TEST=("${ALL_SERVICES[@]}")
    echo -e "${BLUE}Service(s):${NC}  all (${#SERVICES_TO_TEST[@]} services)"
else
    # Check if specified service exists
    if [[ " ${ALL_SERVICES[@]} " =~ " ${SERVICE_FILTER} " ]]; then
        SERVICES_TO_TEST=("$SERVICE_FILTER")
        echo -e "${BLUE}Service(s):${NC}  $SERVICE_FILTER"
    else
        echo -e "${RED}❌ Error: Service '$SERVICE_FILTER' not found${NC}"
        echo "   Available services: ${ALL_SERVICES[*]}"
        exit 1
    fi
fi

# =============================================================================
# Determine Test Strategy Based on Deployment Mode
# =============================================================================

echo ""
USE_API_GATEWAY=false
USE_DIRECT_URLS=false

if [ "$DEPLOYMENT_MODE" = "api-gateway-standard" ] || [ "$DEPLOYMENT_MODE" = "legacy-api-gateway" ]; then
    if [ -n "$API_GATEWAY_URL" ] && [ "$API_GATEWAY_URL" != "Not enabled" ]; then
        USE_API_GATEWAY=true
        echo -e "${GREEN}✅ API Gateway URL: $API_GATEWAY_URL${NC}"
        echo -e "${BLUE}   Mode: API Gateway (Standard Entry Point)${NC}"
    else
        echo -e "${RED}❌ Error: API Gateway enabled but URL not available${NC}"
        exit 1
    fi
elif [ "$DEPLOYMENT_MODE" = "direct-access" ]; then
    USE_DIRECT_URLS=true
    echo -e "${YELLOW}⚠️  Mode: Direct Access (Lambda Function URLs / AppRunner URLs)${NC}"
else
    echo -e "${RED}❌ Error: Unknown deployment mode: $DEPLOYMENT_MODE${NC}"
    exit 1
fi

echo ""

# =============================================================================
# Test Utilities
# =============================================================================

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test
run_test() {
    local test_name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    local check_body="${4:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${MAGENTA}Test $TOTAL_TESTS:${NC} $test_name"

    # Make the request and capture response
    response=$(curl -s -w "\n%{http_code}" "$url" 2>&1)
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    # Check HTTP status code
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}  ✅ HTTP Status: $http_code${NC}"

        # Additional body checks if provided
        if [ -n "$check_body" ]; then
            if echo "$body" | grep -q "$check_body"; then
                echo -e "${GREEN}  ✅ Response contains: '$check_body'${NC}"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                echo -e "${RED}  ❌ Response does not contain: '$check_body'${NC}"
                echo -e "${YELLOW}  Response: ${body:0:200}${NC}"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
        else
            PASSED_TESTS=$((PASSED_TESTS + 1))
        fi
    else
        echo -e "${RED}  ❌ HTTP Status: $http_code (expected $expected_status)${NC}"
        echo -e "${YELLOW}  Response: ${body:0:200}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo ""
}

# Function to test JSON field
test_json_field() {
    local test_name="$1"
    local url="$2"
    local field="$3"
    local expected_value="${4:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${MAGENTA}Test $TOTAL_TESTS:${NC} $test_name"

    # Make the request
    response=$(curl -s "$url" 2>&1)

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}  ⚠️  Skipped (jq not installed)${NC}"
        echo ""
        return
    fi

    # Check if response is valid JSON
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo -e "${RED}  ❌ Invalid JSON response${NC}"
        echo -e "${YELLOW}  Response: ${response:0:200}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo ""
        return
    fi

    # Extract field value
    value=$(echo "$response" | jq -r "$field" 2>/dev/null || echo "null")

    if [ "$value" = "null" ]; then
        echo -e "${RED}  ❌ Field '$field' not found${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    elif [ -n "$expected_value" ] && [ "$value" != "$expected_value" ]; then
        echo -e "${RED}  ❌ Field '$field' = '$value' (expected '$expected_value')${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        echo -e "${GREEN}  ✅ Field '$field' = '$value'${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    echo ""
}

# Function to measure response time
test_response_time() {
    local test_name="$1"
    local url="$2"
    local max_time_ms="${3:-3000}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${MAGENTA}Test $TOTAL_TESTS:${NC} $test_name"

    response_time=$(curl -s -o /dev/null -w "%{time_total}" "$url" 2>&1)
    response_time_ms=$(echo "$response_time * 1000" | bc 2>/dev/null || echo "$response_time")

    # Convert to integer for comparison
    response_time_int=${response_time_ms%.*}

    if [ "$response_time_int" -lt "$max_time_ms" ]; then
        echo -e "${GREEN}  ✅ Response time: ${response_time}s (< ${max_time_ms}ms)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${YELLOW}  ⚠️  Response time: ${response_time}s (slower than expected but functional)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    echo ""
}

# =============================================================================
# Test Functions for Services
# =============================================================================

test_service_via_gateway() {
    local service="$1"
    local service_type="$2"  # "lambda" or "apprunner"
    local base_path=""

    # Determine the base path based on service name and type
    # Lambda 'api' service uses root path, all others use service name as prefix
    if [ "$service_type" = "lambda" ] && [ "$service" = "api" ]; then
        base_path=""
    else
        base_path="$service"
    fi

    if [ "$service_type" = "lambda" ]; then
        echo -e "${BLUE}━━━ Testing ${service} Lambda service (via API Gateway) ━━━${NC}"
    else
        echo -e "${BLUE}━━━ Testing ${service} AppRunner service (via API Gateway) ━━━${NC}"
    fi
    echo ""

    # Construct URLs
    local health_url="${API_GATEWAY_URL}/${base_path}/health"
    local liveness_url="${API_GATEWAY_URL}/${base_path}/liveness"
    local readiness_url="${API_GATEWAY_URL}/${base_path}/readiness"
    local docs_url="${API_GATEWAY_URL}/${base_path}/docs"

    # Remove double slashes if base_path is empty
    health_url=$(echo "$health_url" | sed 's#//#/#g')
    liveness_url=$(echo "$liveness_url" | sed 's#//#/#g')
    readiness_url=$(echo "$readiness_url" | sed 's#//#/#g')
    docs_url=$(echo "$docs_url" | sed 's#//#/#g')

    run_test "${service}: Health check" \
        "$health_url" \
        200 \
        "healthy"

    run_test "${service}: Liveness probe" \
        "$liveness_url" \
        200 \
        "alive"

    run_test "${service}: Readiness probe" \
        "$readiness_url" \
        200 \
        "ready"

    test_json_field "${service}: Health status field" \
        "$health_url" \
        ".status" \
        "healthy"

    run_test "${service}: OpenAPI/Swagger endpoint" \
        "$docs_url" \
        200 \
        "swagger"

    test_response_time "${service}: Response time" \
        "$health_url" \
        3000
}

test_service_direct() {
    local service="$1"
    local service_url="$2"
    local service_type="$3"

    if [ "$service_type" = "lambda" ]; then
        echo -e "${BLUE}━━━ Testing ${service} Lambda service (Direct URL) ━━━${NC}"
    else
        echo -e "${BLUE}━━━ Testing ${service} AppRunner service (Direct URL) ━━━${NC}"
    fi
    echo ""

    run_test "${service}: Health check" \
        "${service_url}/health" \
        200 \
        "healthy"

    run_test "${service}: Liveness probe" \
        "${service_url}/liveness" \
        200 \
        "alive"

    test_json_field "${service}: Health status field" \
        "${service_url}/health" \
        ".status" \
        "healthy"

    test_response_time "${service}: Response time" \
        "${service_url}/health" \
        3000
}

# =============================================================================
# Run Tests
# =============================================================================

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    Running Health Check Tests                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

for service in "${SERVICES_TO_TEST[@]}"; do
    is_lambda=false
    is_apprunner=false

    # Determine service type
    if [[ " ${LAMBDA_SERVICES[@]} " =~ " ${service} " ]]; then
        is_lambda=true
    fi

    if [[ " ${APPRUNNER_SERVICES[@]} " =~ " ${service} " ]]; then
        is_apprunner=true
    fi

    if [ "$USE_API_GATEWAY" = true ]; then
        # Test via API Gateway
        if [ "$is_lambda" = true ]; then
            test_service_via_gateway "$service" "lambda"
        elif [ "$is_apprunner" = true ]; then
            test_service_via_gateway "$service" "apprunner"
        fi
    elif [ "$USE_DIRECT_URLS" = true ]; then
        # Test via Direct URLs
        cd terraform

        if [ "$is_lambda" = true ]; then
            lambda_url=$(terraform output -raw "lambda_${service}_url" 2>/dev/null || echo "")
            if [ -n "$lambda_url" ] && [ "$lambda_url" != "null" ]; then
                cd "$PROJECT_ROOT"
                test_service_direct "$service" "$lambda_url" "lambda"
            else
                cd "$PROJECT_ROOT"
                echo -e "${YELLOW}⚠️  Lambda service '${service}' URL not available${NC}"
                echo ""
            fi
        elif [ "$is_apprunner" = true ]; then
            apprunner_url=$(terraform output -raw "apprunner_${service}_url" 2>/dev/null || echo "")
            if [ -n "$apprunner_url" ] && [ "$apprunner_url" != "null" ]; then
                cd "$PROJECT_ROOT"
                test_service_direct "$service" "$apprunner_url" "apprunner"
            else
                cd "$PROJECT_ROOT"
                echo -e "${YELLOW}⚠️  AppRunner service '${service}' URL not available${NC}"
                echo ""
            fi
        fi
    fi
done

# =============================================================================
# Summary
# =============================================================================

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                         Test Summary                           ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total Tests:  ${TOTAL_TESTS}"
echo -e "${GREEN}Passed:       ${PASSED_TESTS}${NC}"

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed:       ${FAILED_TESTS}${NC}"
else
    echo -e "${GREEN}Failed:       ${FAILED_TESTS}${NC}"
fi

echo ""

# =============================================================================
# Final Result
# =============================================================================

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✅ All Tests Passed! Services Healthy              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📊 Deployment Information:${NC}"
    echo -e "   Environment:     ${ENVIRONMENT}"
    echo -e "   Project:         ${PROJECT_NAME}"
    echo -e "   Deployment Mode: ${DEPLOYMENT_MODE}"
    echo -e "   Services Tested: ${#SERVICES_TO_TEST[@]} (${SERVICES_TO_TEST[*]})"
    echo ""

    if [ "$USE_API_GATEWAY" = true ]; then
        echo -e "${BLUE}🌐 API Gateway:${NC} ${API_GATEWAY_URL}"
        echo -e "${BLUE}📍 Service Endpoints:${NC}"
        for svc in "${SERVICES_TO_TEST[@]}"; do
            if [[ " ${LAMBDA_SERVICES[@]} " =~ " ${svc} " ]]; then
                if [ "$svc" = "api" ]; then
                    echo -e "   - ${svc}: ${API_GATEWAY_URL}/health"
                else
                    echo -e "   - ${svc}: ${API_GATEWAY_URL}/${svc}/health"
                fi
            elif [[ " ${APPRUNNER_SERVICES[@]} " =~ " ${svc} " ]]; then
                echo -e "   - ${svc}: ${API_GATEWAY_URL}/${svc}/health"
            fi
        done
    fi

    echo ""
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║               ❌ Some Tests Failed - Review Above              ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}💡 Troubleshooting Tips:${NC}"
    echo -e "   1. Check service logs: make logs-${ENVIRONMENT}"
    echo -e "   2. Verify deployment: cd terraform && terraform plan"
    echo -e "   3. Check API Gateway settings in AWS Console"
    echo -e "   4. Review CloudWatch Logs for error details"
    echo ""
    exit 1
fi
