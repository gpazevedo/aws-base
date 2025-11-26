#!/bin/bash
# =============================================================================
# Restore Terraform State from Backup
# =============================================================================
# This script restores Terraform state from a backup file
# Usage: ./restore-terraform-state.sh [environment] [backup-source]
# Examples:
#   ./restore-terraform-state.sh dev state-backup-pre-apply.json
#   ./restore-terraform-state.sh prod s3://fingus-terraform-state-production/backups/tfstate-backup-production-20251126-143000-abc1234.json
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

if [ $# -lt 2 ]; then
  echo -e "${RED}❌ Error: Missing required arguments${NC}"
  echo ""
  echo "Usage: $0 [environment] [backup-source]"
  echo ""
  echo "Arguments:"
  echo "  environment    - Target environment (dev, test, production)"
  echo "  backup-source  - Path to backup file or S3 URI"
  echo ""
  echo "Examples:"
  echo "  $0 dev state-backup-pre-apply.json"
  echo "  $0 production s3://fingus-terraform-state-production/backups/tfstate-backup-production-20251126-143000-abc1234.json"
  echo "  $0 prod ./backups/tfstate-backup-production-20251126-143000-abc1234.json"
  echo ""
  exit 1
fi

ENVIRONMENT="$1"
BACKUP_SOURCE="$2"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|production)$ ]]; then
  echo -e "${RED}❌ Error: Invalid environment '${ENVIRONMENT}'${NC}"
  echo "   Valid environments: dev, test, production"
  exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Terraform State Restore Script                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Restore Configuration:${NC}"
echo "   Environment:   ${ENVIRONMENT}"
echo "   Backup Source: ${BACKUP_SOURCE}"
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
# Download Backup if from S3
# =============================================================================

BACKUP_FILE=""

if [[ "$BACKUP_SOURCE" == s3://* ]]; then
  echo -e "${BLUE}📥 Downloading backup from S3...${NC}"

  BACKUP_FILE="./state-restore-$(date +%Y%m%d-%H%M%S).json"

  if aws s3 cp "$BACKUP_SOURCE" "$BACKUP_FILE"; then
    echo -e "${GREEN}✅ Backup downloaded successfully${NC}"
    echo "   Local file: ${BACKUP_FILE}"
  else
    echo -e "${RED}❌ Error: Failed to download backup from S3${NC}"
    exit 1
  fi
else
  BACKUP_FILE="$BACKUP_SOURCE"

  if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}❌ Error: Backup file not found: ${BACKUP_FILE}${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Backup file found${NC}"
  echo "   File: ${BACKUP_FILE}"
fi

echo ""

# =============================================================================
# Validate Backup File
# =============================================================================

echo -e "${BLUE}🔍 Validating backup file...${NC}"

if ! jq empty "$BACKUP_FILE" 2>/dev/null; then
  echo -e "${RED}❌ Error: Backup file is not valid JSON${NC}"
  exit 1
fi

# Check if it looks like a Terraform state file
if ! jq -e '.version' "$BACKUP_FILE" >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  Warning: File may not be a valid Terraform state${NC}"
fi

BACKUP_VERSION=$(jq -r '.version // "unknown"' "$BACKUP_FILE")
BACKUP_TERRAFORM_VERSION=$(jq -r '.terraform_version // "unknown"' "$BACKUP_FILE")
RESOURCE_COUNT=$(jq -r '.resources | length // 0' "$BACKUP_FILE")

echo -e "${GREEN}✅ Backup file validated${NC}"
echo "   State Version:     ${BACKUP_VERSION}"
echo "   Terraform Version: ${BACKUP_TERRAFORM_VERSION}"
echo "   Resources:         ${RESOURCE_COUNT}"
echo ""

# =============================================================================
# Get Current State
# =============================================================================

echo -e "${BLUE}📊 Current state information:${NC}"

cd terraform

if ! terraform init -backend-config=environments/${ENVIRONMENT}-backend.hcl >/dev/null 2>&1; then
  echo -e "${RED}❌ Error: Failed to initialize Terraform${NC}"
  exit 1
fi

# Pull current state for comparison
terraform state pull > current-state.json

CURRENT_RESOURCE_COUNT=$(jq -r '.resources | length // 0' current-state.json)
CURRENT_VERSION=$(jq -r '.version // "unknown"' current-state.json)

echo "   Current Resources: ${CURRENT_RESOURCE_COUNT}"
echo "   Current Version:   ${CURRENT_VERSION}"
echo ""

# =============================================================================
# Safety Backup
# =============================================================================

echo -e "${BLUE}💾 Creating safety backup of current state...${NC}"

SAFETY_BACKUP="state-backup-before-restore-$(date +%Y%m%d-%H%M%S).json"
cp current-state.json "../${SAFETY_BACKUP}"

echo -e "${GREEN}✅ Safety backup created: ${SAFETY_BACKUP}${NC}"
echo ""

# =============================================================================
# Confirmation Prompt
# =============================================================================

echo -e "${YELLOW}⚠️  STATE RESTORE CONFIRMATION${NC}"
echo ""
echo "   Environment:       ${ENVIRONMENT}"
echo "   Current Resources: ${CURRENT_RESOURCE_COUNT}"
echo "   Backup Resources:  ${RESOURCE_COUNT}"
echo "   Safety Backup:     ../${SAFETY_BACKUP}"
echo ""
echo -e "${RED}WARNING: This will replace the current Terraform state!${NC}"
echo ""
read -p "Are you sure you want to proceed with the restore? (yes/no): " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
  echo -e "${YELLOW}❌ Restore cancelled${NC}"
  exit 0
fi

echo ""

# =============================================================================
# Restore State
# =============================================================================

echo -e "${BLUE}🔄 Restoring Terraform state...${NC}"

# Push the backup state
if terraform state push "../${BACKUP_FILE}"; then
  echo -e "${GREEN}✅ State restored successfully${NC}"
else
  echo -e "${RED}❌ Error: Failed to restore state${NC}"
  echo ""
  echo "   You can manually restore using:"
  echo "   cd terraform"
  echo "   terraform state push ../${SAFETY_BACKUP}"
  exit 1
fi

echo ""

# =============================================================================
# Verify Restore
# =============================================================================

echo -e "${BLUE}🔍 Verifying restored state...${NC}"

terraform state pull > restored-state.json

RESTORED_RESOURCE_COUNT=$(jq -r '.resources | length // 0' restored-state.json)

echo "   Restored Resources: ${RESTORED_RESOURCE_COUNT}"

if [ "$RESTORED_RESOURCE_COUNT" == "$RESOURCE_COUNT" ]; then
  echo -e "${GREEN}✅ State restore verified${NC}"
else
  echo -e "${YELLOW}⚠️  Warning: Resource count mismatch${NC}"
  echo "   Expected: ${RESOURCE_COUNT}"
  echo "   Got:      ${RESTORED_RESOURCE_COUNT}"
fi

echo ""

# =============================================================================
# Plan Check
# =============================================================================

echo -e "${BLUE}📋 Checking for infrastructure drift...${NC}"
echo ""

if terraform plan -var-file=environments/${ENVIRONMENT}.tfvars -detailed-exitcode >/dev/null 2>&1; then
  echo -e "${GREEN}✅ No infrastructure drift detected${NC}"
  echo "   Infrastructure matches the restored state"
else
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 2 ]; then
    echo -e "${YELLOW}⚠️  Infrastructure drift detected${NC}"
    echo ""
    echo "   Run 'terraform plan' to see what changed:"
    echo "   cd terraform"
    echo "   terraform plan -var-file=environments/${ENVIRONMENT}.tfvars"
  else
    echo -e "${RED}❌ Error running terraform plan${NC}"
  fi
fi

cd ..

echo ""

# =============================================================================
# Summary
# =============================================================================

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            State Restore Completed Successfully                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Restore Summary:${NC}"
echo "   Environment:       ${ENVIRONMENT}"
echo "   Restored From:     ${BACKUP_SOURCE}"
echo "   Resources:         ${RESTORED_RESOURCE_COUNT}"
echo "   Safety Backup:     ${SAFETY_BACKUP}"
echo ""
echo -e "${BLUE}📊 Next Steps:${NC}"
echo "   1. Review infrastructure drift with: cd terraform && terraform plan"
echo "   2. Apply changes if needed: terraform apply"
echo "   3. Keep safety backup until confirmed: ${SAFETY_BACKUP}"
echo ""

echo -e "${GREEN}✅ State restore process completed${NC}"
