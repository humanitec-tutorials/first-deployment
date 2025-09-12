#!/bin/bash
set -e

# =============================================================================
# SAFE DESTRUCTION SCRIPT FOR HUMANITEC TUTORIAL INFRASTRUCTURE
# =============================================================================
# 
# This script safely destroys the Humanitec tutorial infrastructure with:
# - kubectl context verification to prevent wrong cluster destruction
# - Production environment detection and extra warnings  
# - Explicit user confirmation requiring typed confirmation
# - Proper resource destruction ordering to prevent hanging resources
# 
# SAFETY FEATURES:
# - Verifies kubectl context and displays current cluster information
# - Requires typing "destroy-my-infrastructure" for confirmation
# - Shows 5-second countdown with Ctrl+C escape option
# - Detects potential production contexts and shows extra warnings
# 
# =============================================================================

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=== Destroying Humanitec Tutorial Infrastructure with Proper Ordering ==="

# Safety check function - verify kubectl context and get user confirmation
safety_check() {
    echo -e "${RED}⚠️  DANGER: This script will destroy infrastructure and Kubernetes resources!${NC}"
    echo ""
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
        echo "This script requires kubectl to safely verify the target cluster context."
        exit 1
    fi
    
    # Get current kubectl context
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "NONE")
    
    if [ "$CURRENT_CONTEXT" = "NONE" ]; then
        echo -e "${RED}Error: No kubectl context is currently set${NC}"
        echo "Please set your kubectl context before running this script:"
        echo "  kubectl config use-context <your-context>"
        exit 1
    fi
    
    # Get cluster info
    echo -e "${YELLOW}Current kubectl configuration:${NC}"
    echo "  Context: $CURRENT_CONTEXT"
    
    # Try to get cluster info
    CLUSTER_INFO=$(kubectl config get-contexts "$CURRENT_CONTEXT" --no-headers 2>/dev/null | awk '{print $3}' || echo "Unknown")
    echo "  Cluster: $CLUSTER_INFO"
    
    # Get server URL for additional safety
    SERVER_URL=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$CLUSTER_INFO')].cluster.server}" 2>/dev/null || echo "Unknown")
    echo "  Server: $SERVER_URL"
    
    # Show what will be affected
    echo ""
    echo -e "${RED}This script will:${NC}"
    echo "  1. Delete ALL applications/workloads in the current cluster context"
    echo "  2. Delete ALL PVCs, StatefulSets, and Deployments across ALL namespaces"
    echo "  3. Delete ALL Kubernetes resources (secrets, configmaps, service accounts, etc.)"
    echo "  4. Destroy the entire cloud infrastructure (EKS/GKE clusters, VMs, networking)"
    echo "  5. Delete Humanitec environments and projects"
    echo ""
    
    # Check if this looks like a production context (basic heuristics)
    if [[ "$CURRENT_CONTEXT" == *"prod"* ]] || [[ "$CURRENT_CONTEXT" == *"production"* ]] || [[ "$SERVER_URL" == *"prod"* ]]; then
        echo -e "${RED}🚨 WARNING: Your current context appears to be a PRODUCTION environment!${NC}"
        echo -e "${RED}Context: $CURRENT_CONTEXT${NC}"
        echo ""
    fi
    
    # Final confirmation with explicit typing required
    echo -e "${YELLOW}To proceed with destroying the infrastructure in context '${CURRENT_CONTEXT}':${NC}"
    echo "1. Type exactly: destroy-my-infrastructure"
    echo "2. Press Enter"
    echo ""
    echo -e "${RED}Type anything else to cancel.${NC}"
    echo ""
    
    read -p "Confirmation: " user_input
    
    if [ "$user_input" != "destroy-my-infrastructure" ]; then
        echo -e "${GREEN}Destruction cancelled. No resources were harmed.${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Final confirmation: Destroying infrastructure in 5 seconds...${NC}"
    echo -e "${YELLOW}Press Ctrl+C now to cancel!${NC}"
    for i in {5..1}; do
        echo -e "${YELLOW}$i...${NC}"
        sleep 1
    done
    
    echo -e "${RED}🚀 Starting destruction...${NC}"
    echo ""
}

# Run safety check first
safety_check

# Function to run terraform destroy with specific targets (handles resource indices)
destroy_target() {
    local target="$1"
    echo "Destroying: $target"
    terraform destroy -target="$target" -auto-approve || {
        echo "Warning: Failed to destroy $target, continuing..."
    }
}

# Function to destroy cloud-specific resources (handles count conditions)
destroy_cloud_resources() {
    local pattern="$1"
    echo "Checking for resources matching: $pattern"
    terraform state list | grep -E "$pattern" | while read resource; do
        if [ ! -z "$resource" ]; then
            destroy_target "$resource"
        fi
    done
}

echo "Step 1: Destroying environments (and their workloads) using Humanitec CLI..."

# Function to extract values from terraform state using text parsing
get_tf_state_value() {
    local resource="$1"
    local attribute="$2"
    terraform state show "$resource" 2>/dev/null | grep "^[[:space:]]*${attribute}[[:space:]]*=" | head -1 | awk -F'=' '{print $2}' | tr -d ' "' 
}

# Getting project ID from Terraform state
echo "Extracting project information from Terraform state..."

# Get project ID using simple text parsing
echo "Attempting to extract project ID..."

# Method 1: Use the updated text parsing function
PROJECT_ID=$(get_tf_state_value "platform-orchestrator_project.project" "id")
echo "Method 1 (text parsing 'id'): '$PROJECT_ID'"

echo "Detected Project ID: $PROJECT_ID"

if [ ! -z "$PROJECT_ID" ]; then
    # Check if hctl is available
    if ! command -v hctl &> /dev/null; then
        echo "Warning: hctl not found. Please install Humanitec CLI or delete environments manually"
        echo "Manual deletion commands:"
        echo "  hctl delete environment $PROJECT_ID dev"
        echo "  hctl delete environment $PROJECT_ID score"
    else
        # Delete environments using hctl
        echo "Deleting dev environment with hctl..."
        hctl delete environment "$PROJECT_ID" "dev" || {
            echo "Warning: Failed to delete dev environment, continuing..."
        }
        
        echo "Deleting score environment with hctl..."
        hctl delete environment "$PROJECT_ID" "score" || {
            echo "Warning: Failed to delete score environment, continuing..."
        }
        
        # Wait for cleanup to propagate
        echo "Waiting for environment cleanup to complete..."
        sleep 10
    fi
else
    echo "Warning: Could not determine project ID"
    echo "You may need to manually delete environments before continuing"
    if [ ! -z "$PROJECT_ID" ]; then
        echo "Project: $PROJECT_ID"
    fi
fi

# Remove the environments from Terraform state (they were deleted via hctl)
echo "Removing environments from Terraform state..."
terraform state rm "platform-orchestrator_environment.dev_environment" || {
    echo "Warning: Failed to remove dev_environment from state, continuing..."
}
terraform state rm "platform-orchestrator_environment.score_environment" || {
    echo "Warning: Failed to remove score_environment from state, continuing..."
}

echo "Step 2: Destroying orchestrator management resources..."
destroy_target "platform-orchestrator_project.project"
destroy_target "platform-orchestrator_environment_type.environment_type"

echo "Step 3: Destroying runner rules (AWS and GCP)..."
destroy_cloud_resources "platform-orchestrator_runner_rule\."

echo "Step 4: Destroying runners (AWS and GCP)..."
destroy_cloud_resources "platform-orchestrator_kubernetes_gke_runner\."
destroy_cloud_resources "platform-orchestrator_kubernetes_agent_runner\."

echo "Step 5: Destroying module rules..."
destroy_cloud_resources "platform-orchestrator_module_rule\."

echo "Step 6: Destroying modules..."
destroy_cloud_resources "platform-orchestrator_module\."

echo "Step 7: Destroying resource types..."
destroy_cloud_resources "platform-orchestrator_resource_type\."

echo "Step 8: Cleaning up Kubernetes storage resources first..."
# Clean up PVCs and workloads that might be using storage
echo "Removing any PVCs and workloads that might be using storage..."
kubectl delete pvc --all --all-namespaces --ignore-not-found=true --timeout=30s || true
kubectl delete statefulsets --all --all-namespaces --ignore-not-found=true --timeout=30s || true
kubectl delete deployments --all --all-namespaces --ignore-not-found=true --timeout=30s || true

# Wait a bit for cleanup
sleep 10

echo "Step 9: Destroying Kubernetes resources in clusters..."
# Destroy Kubernetes resources that depend on clusters in proper order
echo "Destroying workload resources..."
destroy_cloud_resources "kubernetes_stateful_set\."
destroy_cloud_resources "kubernetes_deployment\."

echo "Destroying storage resources..."
destroy_cloud_resources "kubernetes_persistent_volume\."
destroy_cloud_resources "kubernetes_storage_class\."

echo "Destroying other Kubernetes resources..."
destroy_cloud_resources "kubernetes_daemonset\."
destroy_cloud_resources "kubernetes_.*role.*\."
destroy_cloud_resources "kubernetes_.*binding.*\."
destroy_cloud_resources "kubernetes_service_account\."
destroy_cloud_resources "kubernetes_secret\."
destroy_cloud_resources "kubernetes_config_map\."
destroy_cloud_resources "kubernetes_namespace\."

echo "Step 10: Destroying infrastructure (clusters, networking, etc.)..."
# Let Terraform handle the rest in dependency order
terraform destroy -auto-approve

echo "=== Destruction complete! ==="