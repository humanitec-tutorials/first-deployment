data "google_client_config" "current" {
  count = local.create_gcp ? 1 : 0
}

# AWS EKS Kubernetes provider configuration
data "aws_eks_cluster" "cluster" {
  count = local.create_aws ? 1 : 0
  name  = aws_eks_cluster.cluster[0].name
}

data "aws_eks_cluster_auth" "cluster" {
  count = local.create_aws ? 1 : 0
  name  = aws_eks_cluster.cluster[0].name
}

# Azure AKS Kubernetes provider configuration
data "azurerm_client_config" "current" {
  count = local.create_azure ? 1 : 0
}

data "azurerm_kubernetes_cluster" "cluster" {
  count               = local.create_azure ? 1 : 0
  name                = azurerm_kubernetes_cluster.cluster[0].name
  resource_group_name = azurerm_kubernetes_cluster.cluster[0].resource_group_name
}

# Dynamic provider configuration based on enabled cloud providers
provider "kubernetes" {
  host = local.create_aws ? data.aws_eks_cluster.cluster[0].endpoint : (
    local.create_gcp ? "https://${google_container_cluster.cluster[0].endpoint}" : (
      local.create_azure ? azurerm_kubernetes_cluster.cluster[0].kube_config.0.host : null
    )
  )

  cluster_ca_certificate = local.create_aws ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data) : (
    local.create_gcp ? base64decode(google_container_cluster.cluster[0].master_auth[0].cluster_ca_certificate) : (
      local.create_azure ? base64decode(azurerm_kubernetes_cluster.cluster[0].kube_config.0.cluster_ca_certificate) : null
    )
  )

  token = local.create_aws ? data.aws_eks_cluster_auth.cluster[0].token : (
    local.create_gcp ? data.google_client_config.current[0].access_token : (
      local.create_azure ? azurerm_kubernetes_cluster.cluster[0].kube_config.0.password : null
    )
  )

  # Azure uses client certificate authentication when password is null
  client_certificate = local.create_azure ? base64decode(azurerm_kubernetes_cluster.cluster[0].kube_config.0.client_certificate) : null
  client_key         = local.create_azure ? base64decode(azurerm_kubernetes_cluster.cluster[0].kube_config.0.client_key) : null
}

provider "helm" {
  kubernetes {
    host = local.create_aws ? data.aws_eks_cluster.cluster[0].endpoint : (
      local.create_gcp ? "https://${google_container_cluster.cluster[0].endpoint}" : (
        local.create_azure ? azurerm_kubernetes_cluster.cluster[0].kube_config.0.host : null
      )
    )

    cluster_ca_certificate = local.create_aws ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data) : (
      local.create_gcp ? base64decode(google_container_cluster.cluster[0].master_auth[0].cluster_ca_certificate) : (
        local.create_azure ? base64decode(azurerm_kubernetes_cluster.cluster[0].kube_config.0.cluster_ca_certificate) : null
      )
    )

    token = local.create_aws ? data.aws_eks_cluster_auth.cluster[0].token : (
      local.create_gcp ? data.google_client_config.current[0].access_token : (
        local.create_azure ? azurerm_kubernetes_cluster.cluster[0].kube_config.0.password : null
      )
    )

    # Azure uses client certificate authentication when password is null
    client_certificate = local.create_azure ? base64decode(azurerm_kubernetes_cluster.cluster[0].kube_config.0.client_certificate) : null
    client_key         = local.create_azure ? base64decode(azurerm_kubernetes_cluster.cluster[0].kube_config.0.client_key) : null
  }
}

resource "kubernetes_namespace" "runner" {
  metadata {
    name = "${local.prefix}-humanitec-runner"
  }

  timeouts {
    delete = "15m"
  }
}
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
    google_service_account.runner,
    azurerm_user_assigned_identity.humanitec_runner,
    azurerm_federated_identity_credential.humanitec_runner,
    kubernetes_secret.aws_creds,
    kubernetes_secret.google_service_account
  ]
}

# AWS IRSA - Add annotations after Helm chart creation
resource "kubernetes_annotations" "aws_irsa_sa" {
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

# Azure Workload Identity - Add annotations and labels after Helm chart creation
resource "kubernetes_annotations" "azure_workload_identity_sa" {
  count = local.create_azure ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = "${local.prefix}-humanitec-runner-sa-inner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  annotations = {
    "azure.workload.identity/client-id" = azurerm_user_assigned_identity.humanitec_runner[0].client_id
  }

  depends_on = [helm_release.humanitec_runner]
}

resource "kubernetes_labels" "azure_workload_identity_sa" {
  count = local.create_azure ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = "${local.prefix}-humanitec-runner-sa-inner"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  labels = {
    "azure.workload.identity/use" = "true"
  }

  depends_on = [helm_release.humanitec_runner]
}


