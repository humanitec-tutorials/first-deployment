data "google_client_config" "current" {}

# AWS EKS Kubernetes provider configuration
data "aws_eks_cluster" "cluster" {
  count = local.create_aws ? 1 : 0
  name  = aws_eks_cluster.cluster[0].name
}

data "aws_eks_cluster_auth" "cluster" {
  count = local.create_aws ? 1 : 0
  name  = aws_eks_cluster.cluster[0].name
}

# Dynamic provider configuration based on enabled cloud providers
# Note: Provider configuration is conditional based on which cloud is enabled
provider "kubernetes" {
  host = local.create_aws ? data.aws_eks_cluster.cluster[0].endpoint : (
    local.create_gcp ? "https://${google_container_cluster.cluster[0].endpoint}" : null
  )
  
  cluster_ca_certificate = local.create_aws ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data) : (
    local.create_gcp ? base64decode(google_container_cluster.cluster[0].master_auth[0].cluster_ca_certificate) : null
  )
  
  token = local.create_aws ? data.aws_eks_cluster_auth.cluster[0].token : (
    local.create_gcp ? data.google_client_config.current.access_token : null
  )
}

resource "kubernetes_namespace" "runner" {
  metadata {
    name = "${local.prefix}-humanitec-runner"
  }
}

resource "kubernetes_service_account" "runner" {
  metadata {
    name      = "${local.prefix}-humanitec-runner-sa"
    namespace = kubernetes_namespace.runner.metadata[0].name
    annotations = merge(
      local.create_gcp ? {
        "iam.gke.io/gcp-service-account" = google_service_account.runner[0].email
      } : {},
      local.create_aws ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.humanitec_runner[0].arn
      } : {}
    )
  }
}

resource "kubernetes_role" "orchestrator_access" {
  metadata {
    name      = "${local.prefix}-humanitec-runner-orchestrator-access"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "get"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "delete"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "list", "watch", "create", "update", "delete"]
  }

}

resource "kubernetes_role_binding" "orchestrator_access" {
  metadata {
    name      = "${local.prefix}-humanitec-runner-orchestrator-access"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.orchestrator_access.metadata[0].name
  }

  dynamic "subject" {
    for_each = local.create_gcp ? [1] : []
    content {
      kind = "User"
      name = google_service_account.runner[0].email
    }
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner.metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "runner_cluster_admin" {
  metadata {
    name = "${local.prefix}-humanitec-runner-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner.metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

# Additional resources for AWS agent runner
resource "kubernetes_service_account" "runner_inner" {
  count = local.create_aws ? 1 : 0
  metadata {
    name      = "${kubernetes_service_account.runner.metadata[0].name}-inner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

resource "kubernetes_role" "runner_inner" {
  count = local.create_aws ? 1 : 0
  metadata {
    name      = "${local.prefix}-humanitec-runner-inner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create", "get", "update"]
  }
}

resource "kubernetes_role_binding" "runner_inner" {
  count = local.create_aws ? 1 : 0
  metadata {
    name      = "${local.prefix}-humanitec-runner-inner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.runner_inner[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner_inner[0].metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

# ClusterRole for broader permissions needed by the inner runner
resource "kubernetes_cluster_role" "runner_inner_cluster" {
  count = local.create_aws ? 1 : 0
  metadata {
    name = "${local.prefix}-humanitec-runner-inner-cluster"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "serviceaccounts"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["create", "get", "list", "watch", "update", "delete"]
  }
}

# ClusterRoleBinding for the inner runner - using cluster-admin for full permissions
resource "kubernetes_cluster_role_binding" "runner_inner_cluster_admin" {
  count = local.create_aws ? 1 : 0
  metadata {
    name = "${local.prefix}-humanitec-runner-inner-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner_inner[0].metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

# Simple hostPath StorageClass for demo - no provisioner needed
resource "kubernetes_storage_class" "hostpath_demo" {
  count = local.create_aws ? 1 : 0
  
  metadata {
    name = "hostpath-demo"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  
  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"
}

# Create a DaemonSet to prepare storage directories with correct permissions
resource "kubernetes_daemonset" "storage_init" {
  count = local.create_aws ? 1 : 0
  
  metadata {
    name = "storage-init"
  }

  spec {
    selector {
      match_labels = {
        name = "storage-init"
      }
    }

    template {
      metadata {
        labels = {
          name = "storage-init"
        }
      }

      spec {
        host_network = true
        
        init_container {
          name  = "storage-setup"
          image = "busybox:1.35"
          
          command = [
            "sh", "-c",
            "mkdir -p /host-tmp/k8s-demo-storage && chmod 777 /host-tmp/k8s-demo-storage && chown 1001:1001 /host-tmp/k8s-demo-storage || true"
          ]
          
          volume_mount {
            name       = "host-tmp"
            mount_path = "/host-tmp"
          }

          security_context {
            privileged = true
          }
        }

        container {
          name  = "sleep"
          image = "busybox:1.35"
          command = ["sleep", "3600"]
        }

        volume {
          name = "host-tmp"
          host_path {
            path = "/tmp"
          }
        }

        toleration {
          operator = "Exists"
        }
      }
    }
  }
}

# Create a simple PersistentVolume for demo purposes
resource "kubernetes_persistent_volume" "demo_storage" {
  count = local.create_aws ? 1 : 0
  
  metadata {
    name = "demo-hostpath-pv"
  }

  spec {
    capacity = {
      storage = "10Gi"
    }
    
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Delete"
    storage_class_name              = kubernetes_storage_class.hostpath_demo[0].metadata[0].name
    
    persistent_volume_source {
      host_path {
        path = "/tmp/k8s-demo-storage"
        type = "DirectoryOrCreate"
      }
    }
    
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/os"
            operator = "In"
            values   = ["linux"]
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_daemonset.storage_init
  ]
}

# Secret for agent runner private key
resource "kubernetes_secret" "agent_runner_key" {
  count = local.create_aws ? 1 : 0
  
  metadata {
    name      = "${local.prefix}-canyon-runner-key"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  type = "Opaque"

  data = {
    "private-key" = tls_private_key.agent_runner_key[0].private_key_pem
  }
}

# Secret for AWS credentials (placeholder - you'll need to populate this)
resource "kubernetes_secret" "aws_creds" {
  count = local.create_aws ? 1 : 0
  
  metadata {
    name      = "${local.prefix}-canyon-runner-aws-creds"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  type = "Opaque"

  data = {
    # These would typically be populated from AWS IAM role or other secure method
    "credentials" = ""
  }
}

# StatefulSet for the agent runner
resource "kubernetes_stateful_set" "agent_runner" {
  count = local.create_aws ? 1 : 0

  metadata {
    name      = "${local.prefix}-canyon-runner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  spec {
    replicas    = 1
    service_name = "${local.prefix}-canyon-runner"
    
    selector {
      match_labels = {
        app = "${local.prefix}-canyon-runner"
      }
    }

    template {
      metadata {
        labels = {
          app = "${local.prefix}-canyon-runner"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.runner.metadata[0].name
        
        container {
          name  = "canyon-runner"
          image = "ghcr.io/humanitec/canyon-runner:v1.6.0"
          
          args = [
            "--remote-connect=https://api.humanitec.dev",
            "remote"
          ]

          env {
            name  = "ORG_ID"
            value = var.humanitec_org
          }

          env {
            name  = "RUNNER_ID"
            value = "${local.prefix}-first-deployment-eks-agent-runner"
          }

          env {
            name  = "RUNNER_LOG_LEVEL"
            value = "debug"
          }

          env {
            name = "PRIVATE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.agent_runner_key[0].metadata[0].name
                key  = "private-key"
              }
            }
          }

          volume_mount {
            name       = "aws-creds"
            mount_path = "/mnt/aws-creds"
            read_only  = true
          }
        }

        volume {
          name = "aws-creds"
          secret {
            secret_name = kubernetes_secret.aws_creds[0].metadata[0].name
          }
        }
      }
    }
  }
}


