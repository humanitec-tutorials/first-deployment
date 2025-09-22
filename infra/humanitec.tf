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

# GKE Runner
resource "platform-orchestrator_kubernetes_gke_runner" "gke_runner" {
  count = local.create_gcp ? 1 : 0

  id          = "${local.prefix}-first-deployment-gke-runner"
  description = "GKE runner for Humanitec Orchestrator to launch runners in all environments"

  runner_configuration = {
    cluster = {
      name        = google_container_cluster.cluster[0].name
      project_id  = var.gcp_project_id
      location    = var.gcp_region
      internal_ip = false
      auth = {
        gcp_audience        = "//iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.wip[0].workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.wip_provider[0].workload_identity_pool_provider_id}"
        gcp_service_account = google_service_account.runner[0].email
      }
    }
    job = {
      namespace       = kubernetes_namespace.runner.metadata[0].name
      service_account = kubernetes_service_account.runner[0].metadata[0].name
      pod_template = jsonencode({
        metadata = {
          labels = {
            "app.kubernetes.io/name" = "humanitec-runner"
          }
        }
        spec = {
          containers = [
            {
              name = "canyon-runner"
              volumeMounts = [
                {
                  name      = "google-service-account"
                  mountPath = "/providers/google-service-account"
                  readOnly  = true
                }
              ],
              securityContext = {
                runAsNonRoot = false,
                runAsUser    = 0,
                runAsGroup   = 0
              }
            }
          ]
          volumes = [
            {
              name = "google-service-account"
              secret = {
                secretName = kubernetes_secret.google_service_account[0].metadata[0].name
              }
            }
          ]
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

# RSA key no longer needed for agent runner approach
# resource "tls_private_key" "runner_key" {
#   count     = local.create_aws ? 1 : 0
#   algorithm = "RSA"
#   rsa_bits  = 2048
# }

# Generate ED25519 keypair for kubernetes-agent-runner
resource "tls_private_key" "agent_runner_key" {
  count     = local.create_aws ? 1 : 0
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

# EKS Agent Runner using kubernetes-agent-runner
resource "platform-orchestrator_kubernetes_agent_runner" "eks_agent_runner" {
  count = local.create_aws ? 1 : 0

  id = "${local.prefix}-first-deployment-eks-agent-runner"
  runner_configuration = {
    key = tls_private_key.agent_runner_key[0].public_key_pem
    job = {
      namespace       = kubernetes_namespace.runner.metadata[0].name
      service_account = "${local.prefix}-humanitec-runner-sa-inner"
      pod_template = jsonencode({
        spec = {
          containers = [{
            name = "canyon-runner"
            env  = []
            volumeMounts = [{
              name      = "aws-creds"
              mountPath = "/mnt/aws-creds"
              readOnly  = true
            }],
            securityContext = {
              runAsNonRoot = false,
              runAsUser    = 0,
              runAsGroup   = 0
            }
          }]
          volumes = [{
            name = "aws-creds"
            secret = {
              secretName = "${local.prefix}-canyon-runner-aws-creds"
            }
          }]
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

resource "platform-orchestrator_runner_rule" "gke_runner_rule" {
  count     = local.create_gcp ? 1 : 0
  runner_id = platform-orchestrator_kubernetes_gke_runner.gke_runner[0].id
}

resource "platform-orchestrator_runner_rule" "eks_agent_runner_rule" {
  count     = local.create_aws ? 1 : 0
  runner_id = platform-orchestrator_kubernetes_agent_runner.eks_agent_runner[0].id
}

resource "platform-orchestrator_environment_type" "environment_type" {
  id           = "${local.prefix}-development"
  display_name = "Development Environment"
}

resource "platform-orchestrator_project" "project" {
  id = "${local.prefix}-tutorial"
  depends_on = [
    platform-orchestrator_runner_rule.gke_runner_rule,
    platform-orchestrator_runner_rule.eks_agent_runner_rule
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
    # Runners that environments depend on
    platform-orchestrator_kubernetes_agent_runner.eks_agent_runner,
    platform-orchestrator_kubernetes_gke_runner.gke_runner,
    platform-orchestrator_runner_rule.eks_agent_runner_rule,
    platform-orchestrator_runner_rule.gke_runner_rule,

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
