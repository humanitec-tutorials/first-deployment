# Call the shared runner integration module
module "runner" {
  source = "../shared/runner-integration"

  prefix                           = var.prefix
  humanitec_org                    = var.humanitec_org
  runner_namespace                 = kubernetes_namespace.runner.metadata[0].name
  runner_service_account_name      = "${var.prefix}-humanitec-runner-sa"
  runner_inner_service_account_name = "${var.prefix}-humanitec-runner-sa-inner"
  cloud_provider                   = "gcp"
  public_key_pem                   = var.public_key_pem
  private_key_pem                  = var.private_key_pem

  # GCP-specific configuration
  gcp_service_account_secret_name = kubernetes_secret.google_service_account.metadata[0].name

  depends_on = [
    google_container_cluster.cluster,
    google_service_account.runner,
    kubernetes_secret.google_service_account,
    kubernetes_namespace.runner
  ]
}
