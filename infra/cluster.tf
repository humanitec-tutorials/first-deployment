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


