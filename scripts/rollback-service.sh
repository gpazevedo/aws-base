#!/bin/bash
# =============================================================================
# Rollback Service to Previous Docker Image
# =============================================================================
# This script rolls back a Lambda or AppRunner service to a previous Docker image
# Usage: ./rollback-service.sh [environment] [service] [target-tag]
# Examples:
#   ./rollback-service.sh dev api api-dev-2025-11-25-18-45-ghi9012
#   ./rollback-service.sh prod worker worker-prod-2025-11-24-12-30-abc1234
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Parse Arguments
# =============================================================================

if [ $# -lt 3 ]; then
  echo -e "${RED}❌ Error: Missing required arguments${NC}"
  echo ""
  echo "Usage: $0 [environment] [service] [target-tag]"
  echo ""
  echo "Arguments:"
  echo "  environment  - Target environment (dev, test, prod)"
  echo "  service      - Service name (api, worker, runner, etc.)"
  echo "  target-tag   - Full image tag to rollback to"
  echo ""
  echo "Examples:"
  echo "  $0 dev api api-dev-2025-11-25-18-45-ghi9012"
  echo "  $0 prod worker worker-prod-2025-11-24-12-30-abc1234"
  echo ""
  exit 1
fi

ENVIRONMENT="$1"
SERVICE="$2"
TARGET_TAG="$3"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
  echo -e "${RED}❌ Error: Invalid environment '${ENVIRONMENT}'${NC}"
  echo "   Valid environments: dev, test, prod"
  exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Service Rollback Script                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Rollback Configuration:${NC}"
echo "   Environment: ${ENVIRONMENT}"
echo "   Service:     ${SERVICE}"
echo "   Target Tag:  ${TARGET_TAG}"
echo ""

# =============================================================================
# Read Configuration
# =============================================================================

echo -e "${BLUE}📖 Reading configuration...${NC}"

# Try to get from environment variables first
if [ -z "$PROJECT_NAME" ] || [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
  echo "   Reading from bootstrap outputs..."

  BOOTSTRAP_DIR="bootstrap"
  if [ ! -d "$BOOTSTRAP_DIR" ]; then
    echo -e "${RED}❌ Error: Bootstrap directory not found${NC}"
    echo "   Please set environment variables or ensure bootstrap is deployed:"
    echo "   - PROJECT_NAME"
    echo "   - AWS_ACCOUNT_ID"
    echo "   - AWS_REGION"
    exit 1
  fi

  cd "$BOOTSTRAP_DIR"

  if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null || echo "")
  fi

  if [ -z "$AWS_ACCOUNT_ID" ]; then
    AWS_ACCOUNT_ID=$(terraform output -raw aws_account_id 2>/dev/null || echo "")
  fi

  if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
  fi

  cd ..
fi

if [ -z "$PROJECT_NAME" ] || [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
  echo -e "${RED}❌ Error: Missing required configuration${NC}"
  echo "   Please set the following environment variables:"
  echo "   - PROJECT_NAME"
  echo "   - AWS_ACCOUNT_ID"
  echo "   - AWS_REGION"
  exit 1
fi

echo -e "${GREEN}✅ Configuration loaded${NC}"
echo "   Project:     ${PROJECT_NAME}"
echo "   AWS Account: ${AWS_ACCOUNT_ID}"
echo "   AWS Region:  ${AWS_REGION}"
echo ""

# =============================================================================
# Validate Target Image Exists
# =============================================================================

echo -e "${BLUE}🔍 Validating target image exists...${NC}"

ECR_REPOSITORY="${PROJECT_NAME}"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${TARGET_TAG}"

# Check if image exists in ECR
IMAGE_EXISTS=$(aws ecr describe-images \
  --repository-name "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}" \
  --image-ids imageTag="${TARGET_TAG}" \
  --query 'imageDetails[0].imageTags[0]' \
  --output text 2>/dev/null || echo "None")

if [ "$IMAGE_EXISTS" == "None" ] || [ -z "$IMAGE_EXISTS" ]; then
  echo -e "${RED}❌ Error: Image tag '${TARGET_TAG}' not found in ECR${NC}"
  echo ""
  echo "Available images for ${SERVICE}-${ENVIRONMENT}:"
  aws ecr describe-images \
    --repository-name "${ECR_REPOSITORY}" \
    --region "${AWS_REGION}" \
    --query "reverse(sort_by(imageDetails[?contains(imageTags[0], '${SERVICE}-${ENVIRONMENT}-')], &imagePushedAt))[0:10].{Tag:imageTags[0],Pushed:imagePushedAt}" \
    --output table 2>/dev/null || echo "  (Unable to list images)"
  echo ""
  exit 1
fi

echo -e "${GREEN}✅ Image found in ECR${NC}"
echo "   Image URI: ${IMAGE_URI}"
echo ""

# =============================================================================
# Detect Service Type (Lambda or AppRunner)
# =============================================================================

echo -e "${BLUE}🔍 Detecting service type...${NC}"

SERVICE_TYPE=""
FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-${SERVICE}"

# Check if Lambda function exists
LAMBDA_EXISTS=$(aws lambda get-function \
  --function-name "${FUNCTION_NAME}" \
  --region "${AWS_REGION}" \
  --query 'Configuration.FunctionName' \
  --output text 2>/dev/null || echo "None")

if [ "$LAMBDA_EXISTS" != "None" ] && [ -n "$LAMBDA_EXISTS" ]; then
  SERVICE_TYPE="lambda"
  echo -e "${GREEN}✅ Detected Lambda function: ${FUNCTION_NAME}${NC}"
else
  # Check if AppRunner service exists
  APPRUNNER_SERVICE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-${SERVICE}"
  SERVICE_ARN=$(aws apprunner list-services \
    --region "${AWS_REGION}" \
    --query "ServiceSummaryList[?ServiceName=='${APPRUNNER_SERVICE_NAME}'].ServiceArn" \
    --output text 2>/dev/null || echo "")

  if [ -n "$SERVICE_ARN" ]; then
    SERVICE_TYPE="apprunner"
    echo -e "${GREEN}✅ Detected App Runner service: ${APPRUNNER_SERVICE_NAME}${NC}"
    echo "   Service ARN: ${SERVICE_ARN}"
  else
    echo -e "${RED}❌ Error: Service '${SERVICE}' not found${NC}"
    echo "   Checked for:"
    echo "   - Lambda function: ${FUNCTION_NAME}"
    echo "   - App Runner service: ${APPRUNNER_SERVICE_NAME}"
    echo ""
    exit 1
  fi
fi

echo ""

# =============================================================================
# Get Current Configuration
# =============================================================================

echo -e "${BLUE}📊 Current service configuration:${NC}"

if [ "$SERVICE_TYPE" == "lambda" ]; then
  CURRENT_IMAGE=$(aws lambda get-function \
    --function-name "${FUNCTION_NAME}" \
    --region "${AWS_REGION}" \
    --query 'Code.ImageUri' \
    --output text)

  echo "   Current Image: ${CURRENT_IMAGE}"

  aws lambda get-function \
    --function-name "${FUNCTION_NAME}" \
    --region "${AWS_REGION}" \
    --query 'Configuration.{Memory:MemorySize,Timeout:Timeout,State:State}' \
    --output table

elif [ "$SERVICE_TYPE" == "apprunner" ]; then
  CURRENT_IMAGE=$(aws apprunner describe-service \
    --service-arn "${SERVICE_ARN}" \
    --region "${AWS_REGION}" \
    --query 'Service.SourceConfiguration.ImageRepository.ImageIdentifier' \
    --output text)

  echo "   Current Image: ${CURRENT_IMAGE}"

  aws apprunner describe-service \
    --service-arn "${SERVICE_ARN}" \
    --region "${AWS_REGION}" \
    --query 'Service.{Status:Status,CPU:InstanceConfiguration.Cpu,Memory:InstanceConfiguration.Memory}' \
    --output table
fi

echo ""

# =============================================================================
# Confirmation Prompt
# =============================================================================

echo -e "${YELLOW}⚠️  ROLLBACK CONFIRMATION${NC}"
echo ""
echo "   Service:       ${SERVICE} (${SERVICE_TYPE})"
echo "   Environment:   ${ENVIRONMENT}"
echo "   Current Image: ${CURRENT_IMAGE}"
echo "   Target Image:  ${IMAGE_URI}"
echo ""
read -p "Are you sure you want to proceed with the rollback? (yes/no): " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
  echo -e "${YELLOW}❌ Rollback cancelled${NC}"
  exit 0
fi

echo ""

# =============================================================================
# Perform Rollback
# =============================================================================

echo -e "${BLUE}🔄 Starting rollback...${NC}"

if [ "$SERVICE_TYPE" == "lambda" ]; then
  # Lambda rollback
  echo "   Updating Lambda function code..."

  aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --image-uri "${IMAGE_URI}" \
    --region "${AWS_REGION}" \
    --no-cli-pager

  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: Failed to update Lambda function${NC}"
    exit 1
  fi

  echo ""
  echo "   Waiting for function update to complete..."

  aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${AWS_REGION}"

  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: Function update timed out or failed${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Lambda function updated successfully${NC}"

elif [ "$SERVICE_TYPE" == "apprunner" ]; then
  # AppRunner rollback
  echo -e "${YELLOW}⚠️  Note: AppRunner services require Terraform for image updates${NC}"
  echo "   Recommended approach: Update via Terraform with target tag"
  echo ""
  echo "   Alternative: Trigger deployment with current ECR configuration"
  echo ""
  read -p "Trigger AppRunner deployment now? This will use the image from ECR. (yes/no): " DEPLOY_NOW

  if [ "$DEPLOY_NOW" == "yes" ]; then
    echo ""
    echo "   Starting AppRunner deployment..."

    aws apprunner start-deployment \
      --service-arn "${SERVICE_ARN}" \
      --region "${AWS_REGION}" \
      --no-cli-pager

    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Error: Failed to start AppRunner deployment${NC}"
      exit 1
    fi

    echo -e "${GREEN}✅ AppRunner deployment started${NC}"
    echo ""
    echo "   Monitoring deployment status (this may take several minutes)..."

    MAX_WAIT=600  # 10 minutes
    ELAPSED=0

    while [ $ELAPSED -lt $MAX_WAIT ]; do
      STATUS=$(aws apprunner describe-service \
        --service-arn "${SERVICE_ARN}" \
        --region "${AWS_REGION}" \
        --query 'Service.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

      echo "   Status: ${STATUS} (${ELAPSED}s elapsed)"

      if [ "$STATUS" == "RUNNING" ]; then
        echo -e "${GREEN}✅ AppRunner deployment completed successfully${NC}"
        break
      elif [ "$STATUS" == "CREATE_FAILED" ] || [ "$STATUS" == "UPDATE_FAILED" ]; then
        echo -e "${RED}❌ AppRunner deployment failed with status: ${STATUS}${NC}"
        exit 1
      elif [ "$STATUS" == "OPERATION_IN_PROGRESS" ]; then
        sleep 30
        ELAPSED=$((ELAPSED + 30))
      else
        echo -e "${YELLOW}⚠️  Unexpected status: ${STATUS}${NC}"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
      fi
    done

    if [ $ELAPSED -ge $MAX_WAIT ]; then
      echo -e "${YELLOW}⚠️  Deployment monitoring timed out after ${MAX_WAIT}s${NC}"
      echo "   Check deployment status manually"
    fi
  else
    echo -e "${YELLOW}⚠️  AppRunner deployment not triggered${NC}"
    echo ""
    echo "   To rollback via Terraform:"
    echo "   cd terraform"
    echo "   terraform apply -var=\"${SERVICE}_image_tag=${TARGET_TAG}\" \\"
    echo "     -var-file=environments/${ENVIRONMENT}.tfvars \\"
    echo "     -target=aws_apprunner_service.${SERVICE}"
    exit 0
  fi
fi

echo ""

# =============================================================================
# Verify Rollback
# =============================================================================

echo -e "${BLUE}🔍 Verifying rollback...${NC}"

if [ "$SERVICE_TYPE" == "lambda" ]; then
  CURRENT_IMAGE=$(aws lambda get-function \
    --function-name "${FUNCTION_NAME}" \
    --region "${AWS_REGION}" \
    --query 'Code.ImageUri' \
    --output text)

  echo "   Current Image: ${CURRENT_IMAGE}"

  if [[ "$CURRENT_IMAGE" == *"${TARGET_TAG}"* ]]; then
    echo -e "${GREEN}✅ Rollback verified - image updated successfully${NC}"
  else
    echo -e "${YELLOW}⚠️  Warning: Image may not have updated correctly${NC}"
  fi

elif [ "$SERVICE_TYPE" == "apprunner" ]; then
  STATUS=$(aws apprunner describe-service \
    --service-arn "${SERVICE_ARN}" \
    --region "${AWS_REGION}" \
    --query 'Service.Status' \
    --output text)

  echo "   Service Status: ${STATUS}"

  if [ "$STATUS" == "RUNNING" ]; then
    echo -e "${GREEN}✅ Service is running${NC}"
  else
    echo -e "${YELLOW}⚠️  Service status: ${STATUS}${NC}"
  fi
fi

echo ""

# =============================================================================
# Run Health Checks
# =============================================================================

echo -e "${BLUE}🏥 Running health checks...${NC}"

HEALTH_SCRIPT="./scripts/test-health.sh"

if [ -f "$HEALTH_SCRIPT" ]; then
  echo "   Executing: ${HEALTH_SCRIPT} ${ENVIRONMENT} ${PROJECT_NAME} ${SERVICE}"
  echo ""

  chmod +x "$HEALTH_SCRIPT"

  if "$HEALTH_SCRIPT" "${ENVIRONMENT}" "${PROJECT_NAME}" "${SERVICE}"; then
    echo ""
    echo -e "${GREEN}✅ Health checks passed${NC}"
  else
    echo ""
    echo -e "${YELLOW}⚠️  Health checks failed or incomplete${NC}"
    echo "   Review the output above for details"
  fi
else
  echo -e "${YELLOW}⚠️  Health check script not found: ${HEALTH_SCRIPT}${NC}"
  echo "   Please verify the service manually"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Rollback Completed Successfully                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Rollback Summary:${NC}"
echo "   Service:     ${SERVICE}"
echo "   Type:        ${SERVICE_TYPE}"
echo "   Environment: ${ENVIRONMENT}"
echo "   Target Tag:  ${TARGET_TAG}"
echo ""
echo -e "${BLUE}📊 Next Steps:${NC}"
echo "   1. Monitor service logs for errors"
echo "   2. Verify application functionality"
echo "   3. Document rollback reason"
echo "   4. Plan fix for the issue"
echo ""

if [ "$SERVICE_TYPE" == "lambda" ]; then
  echo -e "${BLUE}📝 Monitor logs with:${NC}"
  echo "   aws logs tail /aws/lambda/${FUNCTION_NAME} --follow"
elif [ "$SERVICE_TYPE" == "apprunner" ]; then
  echo -e "${BLUE}📝 Monitor logs with:${NC}"
  echo "   aws logs tail /aws/apprunner/${PROJECT_NAME}-${ENVIRONMENT}-${SERVICE} --follow"
fi

echo ""
echo -e "${GREEN}✅ Rollback process completed${NC}"
