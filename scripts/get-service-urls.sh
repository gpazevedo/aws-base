#!/bin/bash
# =============================================================================
# Get All Service URLs
# =============================================================================
# Retrieves URLs for all deployed Lambda functions and AppRunner services
# =============================================================================

set -e

ENVIRONMENT=${1:-dev}  # Default to dev environment

echo "=========================================="
echo "Service URLs for Environment: $ENVIRONMENT"
echo "=========================================="
echo ""

cd terraform

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
  echo "❌ Terraform not initialized. Run: make app-init-$ENVIRONMENT"
  exit 1
fi

echo "📍 Primary Endpoint:"
PRIMARY_ENDPOINT=$(terraform output -raw primary_endpoint 2>/dev/null || echo "Not configured")
echo "   $PRIMARY_ENDPOINT"
echo ""

echo "🔗 API Gateway:"
API_GATEWAY_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "Not enabled")
echo "   $API_GATEWAY_URL"
echo ""

echo "⚡ Lambda Function:"
LAMBDA_URL=$(terraform output -raw lambda_function_url 2>/dev/null || echo "Not enabled or direct access disabled")
LAMBDA_NAME=$(terraform output -raw lambda_function_name 2>/dev/null || echo "Not deployed")
echo "   Name: $LAMBDA_NAME"
echo "   URL:  $LAMBDA_URL"
echo ""

echo "🏃 AppRunner Service:"
APPRUNNER_URL=$(terraform output -raw apprunner_service_url 2>/dev/null || echo "Not deployed")
APPRUNNER_STATUS=$(terraform output -raw apprunner_status 2>/dev/null || echo "Not deployed")
echo "   URL:    $APPRUNNER_URL"
echo "   Status: $APPRUNNER_STATUS"
echo ""

echo "🔑 API Key:"
if terraform output api_key_id &>/dev/null; then
  API_KEY_ID=$(terraform output -raw api_key_id)
  echo "   Enabled: Yes"
  echo "   Key ID:  $API_KEY_ID"
  echo "   To get the API key value, run:"
  echo "   cd terraform && terraform output -raw api_key_value"
else
  echo "   Enabled: No"
fi
echo ""

echo "=========================================="
echo "📋 Quick Test Commands:"
echo "=========================================="
echo ""
if [ "$API_GATEWAY_URL" != "Not enabled" ]; then
  echo "# Test API Gateway endpoint:"
  echo "curl $API_GATEWAY_URL/health"
  echo "curl $API_GATEWAY_URL/greet?name=World"
  echo ""
fi

if [[ "$APPRUNNER_URL" == https://* ]]; then
  echo "# Test AppRunner endpoint:"
  echo "curl $APPRUNNER_URL/health"
  echo "curl $APPRUNNER_URL/api-health"
  echo ""
fi

echo "=========================================="
echo "📊 Deployment Mode:"
DEPLOYMENT_MODE=$(terraform output -raw deployment_mode 2>/dev/null || echo "Unknown")
echo "   $DEPLOYMENT_MODE"
echo "=========================================="
