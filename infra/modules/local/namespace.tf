# Namespace for Humanitec runner
resource "kubernetes_namespace" "runner" {
  metadata {
    name = "${var.prefix}-humanitec-runner"
  }

  depends_on = [null_resource.wait_for_cluster]
}
