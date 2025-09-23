provider "platform-orchestrator" {
  org_id     = var.humanitec_org
  auth_token = var.humanitec_auth_token
  api_url    = "https://api.humanitec.dev"
}

resource "google_service_account_key" "runner_key" {
  count              = local.create_gcp ? 1 : 0
  service_account_id = google_service_account.runner[0].name
}

resource "kubernetes_secret" "google_service_account" {
  count = local.create_gcp ? 1 : 0

  metadata {
    name      = "google-service-account"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  type = "Opaque"

  data = {
    "credentials.json" = base64decode(google_service_account_key.runner_key[0].private_key)
  }
}

# GKE Runner removed - now using unified agent runner for both GCP and AWS

# RSA key no longer needed for agent runner approach
# resource "tls_private_key" "runner_key" {
#   count     = local.create_aws ? 1 : 0
#   algorithm = "RSA"
#   rsa_bits  = 2048
# }

# Generate ED25519 keypair for kubernetes-agent-runner (unified for all clouds)
resource "tls_private_key" "agent_runner_key" {
  algorithm = "ED25519"
}

# TLS certificate resources are no longer needed for agent runner

# Alternative: Use AWS IAM Authenticator for more robust authentication
# This requires creating an aws-auth ConfigMap in the cluster
resource "kubernetes_config_map" "aws_auth" {
  count = local.create_aws ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.eks_nodes[0].arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      },
      {
        rolearn  = aws_iam_role.humanitec_runner[0].arn
        username = "humanitec-runner"
        groups = [
          "system:masters",
        ]
      },
    ])
  }
}

# Unified Agent Runner for both GCP and AWS
resource "platform-orchestrator_kubernetes_agent_runner" "agent_runner" {
  id = "${local.prefix}-first-deployment-agent-runner"
  runner_configuration = {
    key = tls_private_key.agent_runner_key.public_key_pem
    job = {
      namespace       = kubernetes_namespace.runner.metadata[0].name
      service_account = "${local.prefix}-humanitec-runner-sa-inner"
      pod_template = jsonencode({
        spec = {
          containers = [{
            name = "canyon-runner"
            env  = []
            volumeMounts = concat(
              local.create_aws ? [{
                name      = "aws-creds"
                mountPath = "/mnt/aws-creds"
                readOnly  = true
              }] : [],
              local.create_gcp ? [{
                name      = "google-service-account"
                mountPath = "/providers/google-service-account"
                readOnly  = true
              }] : []
            ),
            securityContext = {
              runAsNonRoot = false,
              runAsUser    = 0,
              runAsGroup   = 0
            }
          }]
          volumes = concat(
            local.create_aws ? [{
              name = "aws-creds"
              secret = {
                secretName = "${local.prefix}-canyon-runner-aws-creds"
              }
            }] : [],
            local.create_gcp ? [{
              name = "google-service-account"
              secret = {
                secretName = "google-service-account"
              }
            }] : []
          )
        }
      })
    }
  }
  state_storage_configuration = {
    type = "kubernetes"
    kubernetes_configuration = {
      namespace = kubernetes_namespace.runner.metadata[0].name
    }
  }
}

# GKE runner rule removed - now using unified agent runner rule

resource "platform-orchestrator_runner_rule" "agent_runner_rule" {
  runner_id = platform-orchestrator_kubernetes_agent_runner.agent_runner.id
}

resource "platform-orchestrator_environment_type" "environment_type" {
  id           = "${local.prefix}-development"
  display_name = "Development Environment"
}

resource "platform-orchestrator_project" "project" {
  id = "${local.prefix}-tutorial"
  depends_on = [
    platform-orchestrator_runner_rule.agent_runner_rule
  ]
}

resource "platform-orchestrator_environment" "dev_environment" {
  id          = "dev"
  project_id  = platform-orchestrator_project.project.id
  env_type_id = platform-orchestrator_environment_type.environment_type.id
}

resource "platform-orchestrator_environment" "score_environment" {
  id          = "score"
  project_id  = platform-orchestrator_project.project.id
  env_type_id = platform-orchestrator_environment_type.environment_type.id
}

# Lifecycle management for proper destroy ordering
# This ensures environments are destroyed before their dependencies (runners, projects, etc.)
resource "null_resource" "environment_lifecycle" {
  triggers = {
    # Track environment IDs to detect changes
    dev_environment   = platform-orchestrator_environment.dev_environment.id
    score_environment = platform-orchestrator_environment.score_environment.id
    project_id        = platform-orchestrator_project.project.id
    env_type_id       = platform-orchestrator_environment_type.environment_type.id
  }

  # Make this resource depend on all the infrastructure that environments use
  # During destroy, Terraform will destroy this resource first, then environments,
  # then finally the infrastructure resources
  depends_on = [
    # Unified runner that environments depend on
    platform-orchestrator_kubernetes_agent_runner.agent_runner,
    platform-orchestrator_runner_rule.agent_runner_rule,

    # Project and environment type
    platform-orchestrator_project.project,
    platform-orchestrator_environment_type.environment_type,

    # Module rules that environments use
    platform-orchestrator_module_rule.ansible_score_workload,

    # Underlying infrastructure
    helm_release.humanitec_runner,
    kubernetes_cluster_role_binding.runner_inner_cluster_admin,
    aws_iam_role.humanitec_runner,
    google_service_account.runner
  ]
}
