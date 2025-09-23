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

provider "helm" {
  kubernetes {
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
}

resource "kubernetes_namespace" "runner" {
  metadata {
    name = "${local.prefix}-humanitec-runner"
  }
}

# ServiceAccount is now managed by Helm chart for both GCP and AWS
# The Helm chart will create the service account with proper annotations

# GCP authentication uses service account keys (stored in kubernetes_secret.google_service_account)
# No workload identity annotations needed since we removed workload identity from the cluster

# RBAC is now managed by Helm chart for both GCP and AWS
# The Helm chart will create appropriate RBAC resources

# ClusterRoleBinding for inner runner - ensure cluster-admin permissions
resource "kubernetes_cluster_role_binding" "runner_inner_cluster_admin" {
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
    name      = "${local.prefix}-humanitec-runner-sa-inner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  depends_on = [helm_release.humanitec_runner]
}

# AWS agent runner RBAC resources are now managed by the Helm chart
# The jobs_rbac configuration in the Helm chart creates the necessary service account and RBAC

# Storage resources removed - PostgreSQL now uses ephemeral storage
# This eliminates PVC cleanup issues during destroy operations

# Secret for agent runner private key - managed by Helm chart for AWS
# Keeping the secret creation for backwards compatibility, but Helm chart will manage its own secret

# Create IAM user for inner runner (jobs need explicit AWS credentials)
resource "aws_iam_user" "runner_user" {
  count = local.create_aws ? 1 : 0
  name  = "${local.prefix}-humanitec-runner"
  path  = "/humanitec/"
}

# Create access key for the runner user
resource "aws_iam_access_key" "runner_key" {
  count = local.create_aws ? 1 : 0
  user  = aws_iam_user.runner_user[0].name
}

# Create a standalone policy with the same permissions as the role policy
resource "aws_iam_policy" "humanitec_runner_user" {
  count = local.create_aws ? 1 : 0
  name  = "${local.prefix}-humanitec-runner-user-policy"
  path  = "/humanitec/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:*",
          "eks:*",
          "ec2:*",
          "elasticloadbalancing:*",
          "iam:*",
          "s3:*",
          "sqs:*",
          "sns:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the IAM user
resource "aws_iam_user_policy_attachment" "runner_policy" {
  count      = local.create_aws ? 1 : 0
  user       = aws_iam_user.runner_user[0].name
  policy_arn = aws_iam_policy.humanitec_runner_user[0].arn
}

# Secret for AWS credentials with actual access key credentials
resource "kubernetes_secret" "aws_creds" {
  count = local.create_aws ? 1 : 0

  metadata {
    name      = "${local.prefix}-canyon-runner-aws-creds"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  type = "Opaque"

  data = {
    "credentials" = templatefile("${path.module}/aws-credentials.tpl", {
      aws_access_key_id     = aws_iam_access_key.runner_key[0].id
      aws_secret_access_key = aws_iam_access_key.runner_key[0].secret
      region                = var.aws_region
    })
  }
}

# Deploy Humanitec Kubernetes Agent Runner using Helm chart (unified for all clouds)
resource "helm_release" "humanitec_runner" {
  name       = "${local.prefix}-humanitec-runner"
  repository = "oci://ghcr.io/humanitec/charts"
  chart      = "humanitec-kubernetes-agent-runner"
  version    = "0.1.0"

  namespace        = kubernetes_namespace.runner.metadata[0].name
  create_namespace = false

  recreate_pods = true
  force_update  = true

  values = [
    yamlencode({
      humanitec = {
        orgId      = var.humanitec_org
        runnerId   = "${local.prefix}-first-deployment-agent-runner"
        privateKey = tls_private_key.agent_runner_key.private_key_pem
        logLevel   = "debug"
      }

      rbac = {
        create = true
      }

      jobs_rbac = {
        create               = true
        service_account_name = "${local.prefix}-humanitec-runner-sa-inner"
        namespace            = kubernetes_namespace.runner.metadata[0].name
      }

      serviceAccount = merge(
        {
          create = true
          name   = "${local.prefix}-humanitec-runner-sa"
        },
        local.create_aws ? {
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.humanitec_runner[0].arn
          }
        } : {}
      )
    })
  ]

  depends_on = [
    kubernetes_namespace.runner,
    tls_private_key.agent_runner_key,
    aws_iam_role.humanitec_runner,
    google_service_account.runner,
    kubernetes_secret.aws_creds,
    kubernetes_secret.google_service_account
  ]
}


