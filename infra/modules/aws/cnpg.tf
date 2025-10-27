# CloudNativePG operator for in-cluster Postgres
# This is deployed per-cloud since each cluster needs its own operator instance

resource "kubernetes_namespace" "cnpg" {
  metadata {
    name = "cnpg-system"
  }
}

resource "helm_release" "cloudnative_pg" {
  name       = "cloudnative-pg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = "0.23.0"

  namespace        = kubernetes_namespace.cnpg.metadata[0].name
  create_namespace = false

  depends_on = [
    aws_eks_cluster.cluster,
    kubernetes_namespace.cnpg
  ]
}
