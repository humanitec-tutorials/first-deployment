data "google_client_config" "current" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.cluster.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_namespace" "runner" {
  metadata {
    name = "humanitec-runner"
  }
}

resource "kubernetes_service_account" "runner" {
  metadata {
    name      = "humanitec-runner-sa"
    namespace = kubernetes_namespace.runner.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.runner.email
    }
  }
}

resource "kubernetes_role" "orchestrator_access" {
  metadata {
    name      = "humanitec-runner-orchestrator-access"
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
    name      = "humanitec-runner-orchestrator-access"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.orchestrator_access.metadata[0].name
  }

  subject {
    kind = "User"
    name = google_service_account.runner.email
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner.metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "runner_cluster_admin" {
  metadata {
    name = "humanitec-runner-cluster-admin"
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


