# Runner namespace for this AWS cluster
resource "kubernetes_namespace" "runner" {
  metadata {
    name = "${var.prefix}-humanitec-runner"
  }

  timeouts {
    delete = "15m"
  }
}
