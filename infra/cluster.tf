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

# ServiceAccount for GCP only - AWS service account is managed by Helm chart
resource "kubernetes_service_account" "runner" {
  count = local.create_gcp ? 1 : 0
  metadata {
    name      = "${local.prefix}-humanitec-runner-sa"
    namespace = kubernetes_namespace.runner.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.runner[0].email
    }
  }
}

# Patch the Helm-managed service account with IRSA annotation for AWS
resource "kubernetes_annotations" "runner_irsa" {
  count = local.create_aws ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"

  metadata {
    name      = "${local.prefix}-humanitec-runner-sa"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  annotations = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.humanitec_runner[0].arn
  }

  depends_on = [helm_release.humanitec_runner]
}

# RBAC for GCP only - AWS uses Helm chart managed RBAC
resource "kubernetes_role" "orchestrator_access" {
  count = local.create_gcp ? 1 : 0
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
  count = local.create_gcp ? 1 : 0
  metadata {
    name      = "${local.prefix}-humanitec-runner-orchestrator-access"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.orchestrator_access[0].metadata[0].name
  }

  subject {
    kind = "User"
    name = google_service_account.runner[0].email
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.runner[0].metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "runner_cluster_admin" {
  count = local.create_gcp ? 1 : 0
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
    name      = kubernetes_service_account.runner[0].metadata[0].name
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
}

# ClusterRoleBinding for AWS inner runner - grant cluster-admin permissions
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
    name      = "${local.prefix}-humanitec-runner-sa-inner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }
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

# Deploy Humanitec Kubernetes Agent Runner using Helm chart
resource "helm_release" "humanitec_runner" {
  count = local.create_aws ? 1 : 0

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
        runnerId   = "${local.prefix}-first-deployment-eks-agent-runner"
        privateKey = tls_private_key.agent_runner_key[0].private_key_pem
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

      serviceAccount = {
        create = true
        name   = "${local.prefix}-humanitec-runner-sa"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.runner,
    tls_private_key.agent_runner_key,
    aws_iam_role.humanitec_runner,
    kubernetes_secret.aws_creds
  ]
}


