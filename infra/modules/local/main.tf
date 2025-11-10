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
        - containerPort: 80
          hostPort: ${var.ingress_http_port}
          protocol: TCP
        - containerPort: 443
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

# Install NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  count = local.create_local ? 1 : 0

  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.11.3"
  namespace  = "ingress-nginx"

  create_namespace = true
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      controller = {
        service = {
          type = "NodePort"
        }
        hostPort = {
          enabled = true
          ports = {
            http  = var.ingress_http_port
            https = var.ingress_https_port
          }
        }
        nodeSelector = {
          "ingress-ready" = "true"
        }
        tolerations = [
          {
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Equal"
            effect   = "NoSchedule"
          },
          {
            key      = "node-role.kubernetes.io/master"
            operator = "Equal"
            effect   = "NoSchedule"
          }
        ]
        publishService = {
          enabled = false
        }
        extraArgs = {
          "publish-status-address" = "localhost"
        }
      }
    })
  ]

  depends_on = [null_resource.wait_for_cluster]
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
