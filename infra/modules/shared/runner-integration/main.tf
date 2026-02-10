terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    platform-orchestrator = {
      source  = "humanitec/platform-orchestrator"
      version = ">= 2.9.1"
    }
  }
}

# Deploy Humanitec Kubernetes Agent Runner using Helm chart
resource "helm_release" "humanitec_runner" {
  name       = "${var.prefix}-humanitec-runner"
  repository = "oci://ghcr.io/humanitec/charts"
  chart      = "humanitec-kubernetes-agent-runner"
  version    = "0.1.10"

  namespace        = var.runner_namespace
  create_namespace = false

  recreate_pods = true
  force_update  = true

  values = [
    yamlencode({
      humanitec = {
        orgId    = var.humanitec_org
        runnerId = "${var.prefix}-first-deployment-agent-runner"
        logLevel = "debug"
      }

      rbac = {
        create = true
      }

      jobsRbac = {
        create               = true
        serviceAccountName = var.runner_inner_service_account_name
        namespace            = var.runner_namespace
      }

      serviceAccount = {
        create = true
        name   = var.runner_service_account_name
      }
    })
  ]

  # Set the private key separately as a sensitive value
  set_sensitive = [
    {
      name  = "humanitec.privateKey"
      value = var.private_key_pem
    }
  ]

  depends_on = [platform-orchestrator_kubernetes_agent_runner.agent_runner]
}

# ClusterRoleBinding for inner runner - ensure cluster-admin permissions
resource "kubernetes_cluster_role_binding" "runner_inner_cluster_admin" {
  metadata {
    name = "${var.prefix}-humanitec-runner-inner-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.runner_inner_service_account_name
    namespace = var.runner_namespace
  }

  depends_on = [helm_release.humanitec_runner]
}

# AWS IRSA - Add annotations after Helm chart creation
resource "kubernetes_annotations" "aws_irsa_sa" {
  count = var.cloud_provider == "aws" ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = var.runner_service_account_name
    namespace = var.runner_namespace
  }

  annotations = {
    "eks.amazonaws.com/role-arn" = var.aws_iam_role_arn
  }

  depends_on = [helm_release.humanitec_runner]
}

# Azure Workload Identity - Add annotations and labels after Helm chart creation
resource "kubernetes_annotations" "azure_workload_identity_sa" {
  count = var.cloud_provider == "azure" ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = var.runner_inner_service_account_name
    namespace = var.runner_namespace
  }

  annotations = {
    "azure.workload.identity/client-id" = var.azure_client_id
  }

  depends_on = [helm_release.humanitec_runner]
}

resource "kubernetes_labels" "azure_workload_identity_sa" {
  count = var.cloud_provider == "azure" ? 1 : 0

  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name      = var.runner_inner_service_account_name
    namespace = var.runner_namespace
  }

  labels = {
    "azure.workload.identity/use" = "true"
  }

  depends_on = [helm_release.humanitec_runner]
}

# Build volume mounts based on cloud provider
locals {
  volume_mounts = concat(
    var.cloud_provider == "aws" && var.aws_credentials_secret_name != null ? [{
      name      = "aws-creds"
      mountPath = "/mnt/aws-creds"
      readOnly  = true
    }] : [],
    var.cloud_provider == "gcp" && var.gcp_service_account_secret_name != null ? [{
      name      = "google-service-account"
      mountPath = "/providers/google-service-account"
      readOnly  = true
    }] : [],
    var.cloud_provider == "azure" && var.azure_client_id != null ? [{
      name      = "azure-identity-token"
      mountPath = "/var/run/secrets/azure/tokens"
      readOnly  = true
    }] : []
  )

  volumes = concat(
    var.cloud_provider == "aws" && var.aws_credentials_secret_name != null ? [{
      name = "aws-creds"
      secret = {
        secretName = var.aws_credentials_secret_name
      }
    }] : [],
    var.cloud_provider == "gcp" && var.gcp_service_account_secret_name != null ? [{
      name = "google-service-account"
      secret = {
        secretName = var.gcp_service_account_secret_name
      }
    }] : [],
    var.cloud_provider == "azure" && var.azure_client_id != null ? [{
      name = "azure-identity-token"
      projected = {
        sources = [{
          serviceAccountToken = {
            path              = "azure-identity-token"
            audience          = "api://AzureADTokenExchange"
            expirationSeconds = 3600
          }
        }]
      }
    }] : []
  )

  # Environment variables for cloud provider authentication
  env_vars = var.cloud_provider == "azure" && var.azure_client_id != null ? [
    {
      name  = "AZURE_CLIENT_ID"
      value = var.azure_client_id
    },
    {
      name  = "AZURE_TENANT_ID"
      value = var.azure_tenant_id
    },
    {
      name  = "AZURE_SUBSCRIPTION_ID"
      value = var.azure_subscription_id
    },
    {
      name  = "AZURE_FEDERATED_TOKEN_FILE"
      value = "/var/run/secrets/azure/tokens/azure-identity-token"
    }
  ] : []

  pod_metadata = var.cloud_provider == "azure" ? {
    labels = {
      "azure.workload.identity/use" = "true"
    }
  } : {}
}

# Platform Orchestrator Runner Configuration
resource "platform-orchestrator_kubernetes_agent_runner" "agent_runner" {
  id = "${var.prefix}-first-deployment-agent-runner"
  runner_configuration = {
    key = var.public_key_pem
    job = {
      namespace                   = var.runner_namespace
      service_account             = var.runner_inner_service_account_name
      service_account_annotations = var.cloud_provider == "azure" && var.azure_client_id != null ? {
        "azure.workload.identity/client-id" = var.azure_client_id
      } : {}
      pod_template = jsonencode({
        metadata = local.pod_metadata
        spec = {
          containers = [{
            name         = "canyon-runner"
            env          = local.env_vars
            volumeMounts = local.volume_mounts
            securityContext = {
              runAsNonRoot             = false,
              runAsUser                = 0,
              runAsGroup               = 0,
              privileged               = true,
              allowPrivilegeEscalation = true
            }
          }]
          volumes = local.volumes
        }
      })
    }
  }
  state_storage_configuration = {
    type = "kubernetes"
    kubernetes_configuration = {
      namespace = var.runner_namespace
    }
  }
}

# Runner rule
resource "platform-orchestrator_runner_rule" "agent_runner_rule" {
  runner_id = platform-orchestrator_kubernetes_agent_runner.agent_runner.id
}
