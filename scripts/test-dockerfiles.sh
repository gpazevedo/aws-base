#!/bin/bash
# =============================================================================
# Test All Dockerfiles for Dependency Installation
# =============================================================================
# This script builds and tests all three Dockerfiles to ensure dependencies
# are properly installed and accessible
# =============================================================================

set -e

SERVICE=${1:-api}
PLATFORM=${2:-linux/arm64}

echo "=================================================="
echo "🐳 Testing All Dockerfiles"
echo "=================================================="
echo "Service: $SERVICE"
echo "Platform: $PLATFORM"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test function
test_dockerfile() {
    local dockerfile=$1
    local image_name=$2
    local description=$3

    echo ""
    echo "=================================================="
    echo "Testing: $description"
    echo "Dockerfile: $dockerfile"
    echo "=================================================="

    # Build
    echo "📦 Building image..."
    if docker build \
        --platform=$PLATFORM \
        --build-arg SERVICE_FOLDER=$SERVICE \
        -f backend/$dockerfile \
        -t $image_name \
        backend/ > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Build successful${NC}"
    else
        echo -e "${RED}❌ Build failed${NC}"
        return 1
    fi

    # Test Python path
    echo "🔍 Checking Python path..."
    docker run --rm --platform=$PLATFORM \
        --entrypoint python \
        $image_name \
        -c "import sys; print('Python path OK')" > /dev/null 2>&1
    echo -e "${GREEN}✅ Python path accessible${NC}"

    # Test httpx import
    echo "🔍 Testing httpx import..."
    if docker run --rm --platform=$PLATFORM \
        --entrypoint python \
        $image_name \
        -c "import httpx; print(f'httpx {httpx.__version__}')" 2>&1 | grep -q "httpx"; then
        echo -e "${GREEN}✅ httpx imported successfully${NC}"
    else
        echo -e "${RED}❌ httpx import failed${NC}"
        return 1
    fi

    # Test fastapi import
    echo "🔍 Testing fastapi import..."
    if docker run --rm --platform=$PLATFORM \
        --entrypoint python \
        $image_name \
        -c "import fastapi; print(f'fastapi {fastapi.__version__}')" 2>&1 | grep -q "fastapi"; then
        echo -e "${GREEN}✅ fastapi imported successfully${NC}"
    else
        echo -e "${RED}❌ fastapi import failed${NC}"
        return 1
    fi

    # Test uvicorn import
    echo "🔍 Testing uvicorn import..."
    if docker run --rm --platform=$PLATFORM \
        --entrypoint python \
        $image_name \
        -c "import uvicorn; print(f'uvicorn {uvicorn.__version__}')" 2>&1 | grep -q "uvicorn"; then
        echo -e "${GREEN}✅ uvicorn imported successfully${NC}"
    else
        echo -e "${RED}❌ uvicorn import failed${NC}"
        return 1
    fi

    # List installed packages
    echo "📋 Listing installed packages..."
    docker run --rm --platform=$PLATFORM \
        --entrypoint /bin/bash \
        $image_name \
        -c "python -m pip list | grep -E '(httpx|fastapi|uvicorn|mangum|boto3)'" || true

    echo -e "${GREEN}✅ All tests passed for $description${NC}"
    return 0
}

# Test Lambda Dockerfile
if test_dockerfile "Dockerfile.lambda" "test-lambda:latest" "Lambda (Single-stage)"; then
    LAMBDA_RESULT="✅ PASSED"
else
    LAMBDA_RESULT="❌ FAILED"
fi

# Test AppRunner Dockerfile
if test_dockerfile "Dockerfile.apprunner" "test-apprunner:latest" "App Runner (Single-stage)"; then
    APPRUNNER_RESULT="✅ PASSED"
else
    APPRUNNER_RESULT="❌ FAILED"
fi

# Test EKS Dockerfile
if test_dockerfile "Dockerfile.eks" "test-eks:latest" "EKS (Multi-stage)"; then
    EKS_RESULT="✅ PASSED"
else
    EKS_RESULT="❌ FAILED"
fi

# Summary
echo ""
echo "=================================================="
echo "📊 Test Summary"
echo "=================================================="
echo "Lambda (Dockerfile.lambda):     $LAMBDA_RESULT"
echo "App Runner (Dockerfile.apprunner): $APPRUNNER_RESULT"
echo "EKS (Dockerfile.eks):           $EKS_RESULT"
echo ""

# Check if all passed
if [[ "$LAMBDA_RESULT" == *"PASSED"* ]] && \
   [[ "$APPRUNNER_RESULT" == *"PASSED"* ]] && \
   [[ "$EKS_RESULT" == *"PASSED"* ]]; then
    echo -e "${GREEN}✅ All Dockerfiles passed tests!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Push images to ECR: ./scripts/docker-push.sh dev $SERVICE Dockerfile.lambda"
    echo "2. Update Lambda: aws lambda update-function-code --function-name <name> --image-uri <uri>"
    echo "3. Test deployment: curl <endpoint>/health"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please review the errors above.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "- Check Dockerfile for correct dependency installation"
    echo "- Ensure UV_SYSTEM_PYTHON=1 is set"
    echo "- For multi-stage builds, verify site-packages are copied"
    echo "- See docs/TROUBLESHOOTING-DOCKER-DEPENDENCIES.md"
    exit 1
fi
