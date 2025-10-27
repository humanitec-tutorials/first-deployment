# Call the shared runner integration module
module "runner" {
  source = "../shared/runner-integration"

  prefix                            = var.prefix
  humanitec_org                     = var.humanitec_org
  runner_namespace                  = kubernetes_namespace.runner.metadata[0].name
  runner_service_account_name       = "${var.prefix}-humanitec-runner-sa"
  runner_inner_service_account_name = "${var.prefix}-humanitec-runner-sa-inner"
  cloud_provider                    = "aws"
  public_key_pem                    = var.public_key_pem
  private_key_pem                   = var.private_key_pem

  # AWS-specific configuration
  aws_iam_role_arn             = aws_iam_role.humanitec_runner.arn
  aws_credentials_secret_name  = kubernetes_secret.aws_creds.metadata[0].name

  depends_on = [
    aws_eks_cluster.cluster,
    aws_iam_role.humanitec_runner,
    kubernetes_secret.aws_creds,
    kubernetes_config_map.aws_auth,
    kubernetes_namespace.runner
  ]
}
