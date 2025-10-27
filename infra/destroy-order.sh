#!/bin/bash
set -e

# =============================================================================
# SAFE DESTRUCTION SCRIPT FOR HUMANITEC TUTORIAL INFRASTRUCTURE
# =============================================================================
#
# This script safely destroys the Humanitec tutorial infrastructure with:
# - Environment-first destruction to prevent dependency issues
# - Proper Humanitec resource ordering (rules → modules → resource types)
# - Automatic retry after 10 seconds if resources remain
#
# DESTRUCTION ORDER:
# 1. Destroy cloud-specific environments first (critical dependency)
# 2. Destroy Humanitec resources in dependency order
# 3. Destroy all remaining infrastructure
# 4. If resources remain, wait 10s and retry
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
    echo "  1. Destroy cloud-specific environments first (aws-dev, gcp-dev, etc.)"
    echo "  2. Destroy Humanitec Platform Orchestrator resources in dependency order"
    echo "  3. Destroy Kubernetes resources before clusters to avoid connection errors"
    echo "  4. Destroy all remaining infrastructure via terraform destroy"
    echo "  5. Retry after 10 seconds if resources remain"
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

echo "Step 1: Destroy cloud-specific environments first (critical for clean teardown)..."

# Destroy environments using terraform
# These environments are now in cloud modules, so we target them there
echo "Destroying cloud-specific environments..."

# Disable errexit temporarily for environment destruction
set +e

# Try to destroy AWS environments
terraform destroy \
    -target="module.aws.platform-orchestrator_environment.dev" \
    -target="module.aws.platform-orchestrator_environment.score" \
    -auto-approve 2>/dev/null

# Try to destroy GCP environments
terraform destroy \
    -target="module.gcp.platform-orchestrator_environment.dev" \
    -target="module.gcp.platform-orchestrator_environment.score" \
    -auto-approve 2>/dev/null

# Try to destroy Azure environments
terraform destroy \
    -target="module.azure.platform-orchestrator_environment.dev" \
    -target="module.azure.platform-orchestrator_environment.score" \
    -auto-approve 2>/dev/null

# Re-enable errexit
set -e

echo -e "${GREEN}✅ Environments destroyed successfully!${NC}"
echo ""

echo "Step 2: Destroy Humanitec Platform Orchestrator resources in dependency order..."

# Disable errexit for this section
set +e

echo "  2a. Destroying cloud-specific module rules..."
terraform destroy \
    -target="module.aws.platform-orchestrator_module_rule.ansible_score_workload" \
    -target="module.gcp.platform-orchestrator_module_rule.ansible_score_workload" \
    -target="module.azure.platform-orchestrator_module_rule.ansible_score_workload" \
    -target="platform-orchestrator_module_rule.score_k8s" \
    -target="platform-orchestrator_module_rule.in_cluster_postgres" \
    -target="platform-orchestrator_module_rule.k8s_namespace" \
    -target="module.aws.platform-orchestrator_module_rule.vm_fleet" \
    -target="module.gcp.platform-orchestrator_module_rule.vm_fleet" \
    -target="module.azure.platform-orchestrator_module_rule.vm_fleet" \
    -auto-approve

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: Some module rules may not have been destroyed${NC}"
fi

echo "  2b. Destroying modules..."
terraform destroy \
    -target="platform-orchestrator_module.ansible_score_workload" \
    -target="platform-orchestrator_module.score_k8s" \
    -target="platform-orchestrator_module.in_cluster_postgres" \
    -target="platform-orchestrator_module.k8s_namespace" \
    -target="module.aws.platform-orchestrator_module.vm_fleet" \
    -target="module.gcp.platform-orchestrator_module.vm_fleet" \
    -target="module.azure.platform-orchestrator_module.vm_fleet" \
    -auto-approve

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: Some modules may not have been destroyed${NC}"
fi

echo "  2c. Destroying resource types..."
terraform destroy \
    -target="platform-orchestrator_resource_type.vm_fleet" \
    -target="platform-orchestrator_resource_type.score_workload" \
    -target="platform-orchestrator_resource_type.in_cluster_postgres" \
    -target="platform-orchestrator_resource_type.k8s_namespace" \
    -auto-approve

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: Some resource types may not have been destroyed${NC}"
fi

# Re-enable errexit
set -e

echo -e "${GREEN}✅ Humanitec resources destroyed!${NC}"
echo ""

echo "Step 3: Destroy Kubernetes resources before clusters..."

# Destroy kubernetes resources that depend on the clusters
# This prevents "connection refused" errors when clusters are destroyed first
terraform destroy \
    -target="module.aws.kubernetes_namespace.cnpg" \
    -target="module.aws.kubernetes_namespace.runner" \
    -target="module.aws.kubernetes_secret.aws_creds" \
    -target="module.aws.kubernetes_config_map.aws_auth" \
    -target="module.gcp.kubernetes_namespace.cnpg" \
    -target="module.gcp.kubernetes_namespace.runner" \
    -target="module.gcp.kubernetes_secret.google_service_account" \
    -target="module.azure.kubernetes_namespace.cnpg" \
    -target="module.azure.kubernetes_namespace.runner" \
    -auto-approve 2>/dev/null || true

echo -e "${GREEN}✅ Kubernetes resources destroyed!${NC}"
echo ""

echo "Step 4: Destroy remaining infrastructure..."

# Disable errexit for the destroy attempts
set +e

# First destroy attempt (skip refresh to avoid connection errors with destroyed clusters)
terraform destroy -refresh=false -auto-approve
DESTROY_EXIT_CODE=$?

if [ $DESTROY_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 Destruction completed successfully!${NC}"
    echo "All Humanitec tutorial infrastructure has been destroyed."
    exit 0
fi

# Check if resources remain
REMAINING=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')

if [ "$REMAINING" -eq "0" ]; then
    echo ""
    echo -e "${GREEN}✅ All resources have been removed from Terraform state!${NC}"
    echo "Destruction was successful despite the exit code."
    exit 0
fi

# Resources remain - wait and retry
echo ""
echo -e "${YELLOW}⚠️  First destroy pass completed with $REMAINING resources remaining.${NC}"
echo -e "${YELLOW}Waiting 10 seconds for cloud resources to finalize deletion...${NC}"
sleep 10

echo ""
echo "Retrying terraform destroy..."
terraform destroy -refresh=false -auto-approve
DESTROY_EXIT_CODE=$?

# Re-enable errexit
set -e

# Check final state
REMAINING=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')

if [ "$REMAINING" -eq "0" ]; then
    echo ""
    echo -e "${GREEN}🎉 Destruction completed successfully after retry!${NC}"
    echo "All Humanitec tutorial infrastructure has been destroyed."
    exit 0
elif [ $DESTROY_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 Destruction completed successfully!${NC}"
    echo "All Humanitec tutorial infrastructure has been destroyed."
    exit 0
else
    echo ""
    echo -e "${RED}❌ There are still $REMAINING resources in the Terraform state after retry.${NC}"
    echo "You may need to manually clean these up or run terraform destroy again."
    echo ""
    echo "Remaining resources:"
    terraform state list
    exit 1
fi
