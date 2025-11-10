#!/bin/bash
# Script to apply local KinD infrastructure in stages
# This is necessary because Terraform providers need the cluster context to exist

set -e

echo "========================================="
echo "Stage 1: Creating KinD cluster"
echo "========================================="

# First, create the KinD cluster and wait resources
terraform apply -target=module.local.null_resource.kind_cluster -target=module.local.null_resource.wait_for_cluster -auto-approve

echo ""
echo "========================================="
echo "Stage 2: Applying remaining resources"
echo "========================================="

# Now that the cluster exists, apply everything else
terraform apply -auto-approve

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Your local KinD cluster is ready!"
echo ""
echo "Cluster name: $(terraform output -raw prefix 2>/dev/null || echo 'unknown')-first-deployment-local"
echo "Kubeconfig context: kind-$(terraform output -raw prefix 2>/dev/null || echo 'unknown')-first-deployment-local"
echo ""
echo "To use the cluster:"
echo "  kubectl config use-context kind-$(terraform output -raw prefix 2>/dev/null || echo 'unknown')-first-deployment-local"
echo ""
echo "To deploy applications:"
echo "  hctl deploy $(terraform output -raw project_id 2>/dev/null || echo 'project') $(terraform output -raw prefix 2>/dev/null || echo 'prefix')-local-dev ../manifests/manifest2.yaml"
echo ""
echo "Applications will be accessible at:"
echo "  http://<app-name>.localtest.me"
echo ""
