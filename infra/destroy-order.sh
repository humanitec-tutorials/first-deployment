#!/bin/bash
set -e

# =============================================================================
# SAFE DESTRUCTION SCRIPT FOR HUMANITEC TUTORIAL INFRASTRUCTURE
# =============================================================================
#
# This script safely destroys the Humanitec tutorial infrastructure with:
# - Environment-first destruction to prevent dependency issues
# - Proper error handling if environments cannot be deleted
# - Simplified approach leveraging Terraform lifecycle dependencies
#
# DESTRUCTION ORDER:
# 1. Destroy environments first (critical dependency)
# 2. If environments destroy successfully, proceed with full terraform destroy
# 3. If environments fail to destroy, halt and report the issue
#
# =============================================================================

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=== Destroying Humanitec Tutorial Infrastructure with Proper Ordering ==="

# Simple safety check with user confirmation
safety_check() {
    echo -e "${RED}⚠️  DANGER: This will destroy all Humanitec tutorial infrastructure!${NC}"
    echo ""
    echo -e "${YELLOW}This script will:${NC}"
    echo "  1. Destroy Humanitec environments first (critical for clean teardown)"
    echo "  2. Destroy all remaining infrastructure via terraform destroy"
    echo ""

    echo -e "${YELLOW}To proceed, type exactly: destroy-my-infrastructure${NC}"
    echo -e "${RED}Type anything else to cancel.${NC}"
    echo ""

    read -p "Confirmation: " user_input

    if [ "$user_input" != "destroy-my-infrastructure" ]; then
        echo -e "${GREEN}Destruction cancelled. No resources were harmed.${NC}"
        exit 0
    fi

    echo -e "${RED}🚀 Starting destruction...${NC}"
    echo ""
}

# Run safety check first
safety_check

echo "Step 1: Destroy environments first (critical for clean teardown)..."

# Destroy environments using terraform (leveraging the null_resource lifecycle dependency)
echo "Destroying Humanitec environments..."
terraform destroy \
    -target="platform-orchestrator_environment.dev_environment" \
    -target="platform-orchestrator_environment.score_environment" \
    -auto-approve

# Check if the targeted destroy was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ CRITICAL ERROR: Failed to destroy environments!${NC}"
    echo ""
    echo -e "${YELLOW}This typically indicates:${NC}"
    echo "  • Active deployments in the environments"
    echo "  • Humanitec API connectivity issues"
    echo "  • Resource locks or dependencies"
    echo ""
    echo -e "${RED}STOPPING: Cannot proceed with infrastructure destruction while environments exist.${NC}"
    echo -e "${YELLOW}Manual remediation may be required:${NC}"
    echo "  1. Check for active deployments: hctl get deployments"
    echo "  2. Delete deployments manually if needed"
    echo "  3. Check Humanitec org connectivity"
    echo "  4. Re-run this script"
    exit 1
fi

echo -e "${GREEN}✅ Environments destroyed successfully!${NC}"
echo ""

echo "Step 2: Destroy remaining infrastructure..."
echo "All remaining resources will be destroyed in proper dependency order via Terraform..."

# With environments gone and the null_resource lifecycle dependency,
# terraform destroy should now work cleanly
terraform destroy -auto-approve

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 Destruction completed successfully!${NC}"
    echo "All Humanitec tutorial infrastructure has been destroyed."
else
    echo ""
    echo -e "${RED}❌ Some resources may not have been destroyed completely.${NC}"
    echo -e "${YELLOW}Check the Terraform output above for details.${NC}"
    exit 1
fi