#!/bin/bash
set -e

echo "=== Destroying Humanitec Tutorial Infrastructure with Proper Ordering ==="

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

# Function to extract values from terraform state using JSON output
get_tf_state_value() {
    local resource="$1"
    local path="$2"
    terraform state show -json "$resource" 2>/dev/null | jq -r "$path" 2>/dev/null
}

# Getting project ID from Terraform state
echo "Extracting project information from Terraform state..."

# Get project ID - try multiple approaches
echo "Attempting to extract project ID..."

# Method 1: JSON path .values.id
PROJECT_ID=$(get_tf_state_value "platform-orchestrator_project.project" ".values.id")
echo "Method 1 (.values.id): '$PROJECT_ID'"

# Method 2: JSON path .instances[0].attributes.id
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    PROJECT_ID=$(get_tf_state_value "platform-orchestrator_project.project" ".instances[0].attributes.id")
    echo "Method 2 (.instances[0].attributes.id): '$PROJECT_ID'"
fi

# Method 3: Simple text parsing of terraform state show
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    PROJECT_ID=$(terraform state show platform-orchestrator_project.project 2>/dev/null | grep "id.*=" | head -1 | awk '{print $3}' | tr -d '"')
    echo "Method 3 (text parsing): '$PROJECT_ID'"
fi

# Method 4: Direct terraform output if available
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    PROJECT_ID=$(terraform output -raw project_id 2>/dev/null)
    echo "Method 4 (terraform output): '$PROJECT_ID'"
fi

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
        sleep 15
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