locals {
  cluster_name = "${var.prefix}-${var.cluster_name}"
  create_local = var.enabled
}

# KinD cluster configuration
resource "null_resource" "kind_cluster" {
  count = local.create_local ? 1 : 0

  # Create KinD cluster with ingress-ready configuration
  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOF | kind create cluster --name ${local.cluster_name} --config=-
      kind: Cluster
      apiVersion: kind.x-k8s.io/v1alpha4
      nodes:
      - role: control-plane
        kubeadmConfigPatches:
        - |
          kind: InitConfiguration
          nodeRegistration:
            kubeletExtraArgs:
              node-labels: "ingress-ready=true"
        extraPortMappings:
        - containerPort: 10080
          hostPort: ${var.ingress_http_port}
          protocol: TCP
        - containerPort: 10443
          hostPort: ${var.ingress_https_port}
          protocol: TCP
      EOF
    EOT
  }

  # Cleanup on destroy
  provisioner "local-exec" {
    when    = destroy
    command = "kind delete cluster --name ${self.triggers.cluster_name} || true"
  }

  triggers = {
    cluster_name = local.cluster_name
    config_hash  = md5(jsonencode({
      http_port  = var.ingress_http_port
      https_port = var.ingress_https_port
    }))
  }
}

# Wait for cluster to be ready
resource "null_resource" "wait_for_cluster" {
  count = local.create_local ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl --context kind-${local.cluster_name} wait --for=condition=Ready nodes --all --timeout=300s"
  }

  depends_on = [null_resource.kind_cluster]
}

# Install CloudNativePG operator for in-cluster Postgres
resource "helm_release" "cnpg" {
  count = local.create_local ? 1 : 0

  name       = "cnpg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = "0.22.1"
  namespace  = "cnpg-system"

  create_namespace = true
  wait             = true
  timeout          = 300

  depends_on = [null_resource.wait_for_cluster]
}
