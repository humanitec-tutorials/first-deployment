provider "platform-orchestrator" {
  org_id     = var.humanitec_org
  auth_token = var.humanitec_auth_token
  api_url    = "https://api.humanitec.dev"
}

resource "google_service_account_key" "runner_key" {
  count = local.create_gcp ? 1 : 0
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
      service_account = kubernetes_service_account.runner.metadata[0].name
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

# TLS resources for EKS runner client certificate authentication
resource "tls_private_key" "runner_key" {
  count     = local.create_aws ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate Ed25519 keypair for kubernetes-agent-runner
resource "tls_private_key" "agent_runner_key" {
  count     = local.create_aws ? 1 : 0
  algorithm = "Ed25519"
}

resource "tls_cert_request" "runner_csr" {
  count           = local.create_aws ? 1 : 0
  private_key_pem = tls_private_key.runner_key[0].private_key_pem

  subject {
    common_name  = "humanitec-runner"
    organization = "system:masters"
  }
}

# Self-signed certificate for demonstration purposes
resource "tls_self_signed_cert" "runner_cert" {
  count             = local.create_aws ? 1 : 0
  private_key_pem   = tls_private_key.runner_key[0].private_key_pem
  is_ca_certificate = false

  subject {
    common_name  = "humanitec-runner"
    organization = "system:masters"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "client_auth",
  ]
}

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

# EKS Runner using generic Kubernetes runner
resource "platform-orchestrator_kubernetes_runner" "eks_runner" {
  count = local.create_aws ? 1 : 0

  id          = "${local.prefix}-first-deployment-eks-runner"
  description = "EKS runner for Humanitec Orchestrator to launch runners in all environments"

  runner_configuration = {
    cluster = {
      cluster_data = {
        server                     = aws_eks_cluster.cluster[0].endpoint
        certificate_authority_data = aws_eks_cluster.cluster[0].certificate_authority[0].data
      }
      auth = {
        client_certificate_data = base64encode(tls_self_signed_cert.runner_cert[0].cert_pem)
        client_key_data        = base64encode(tls_private_key.runner_key[0].private_key_pem)
      }
    }
    job = {
      namespace       = kubernetes_namespace.runner.metadata[0].name
      service_account = kubernetes_service_account.runner.metadata[0].name
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
              securityContext = {
                runAsNonRoot = false,
                runAsUser    = 0,
                runAsGroup   = 0
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

resource "platform-orchestrator_runner_rule" "gke_runner_rule" {
  count = local.create_gcp ? 1 : 0
  runner_id = platform-orchestrator_kubernetes_gke_runner.gke_runner[0].id
}

resource "platform-orchestrator_runner_rule" "eks_runner_rule" {
  count = local.create_aws ? 1 : 0
  runner_id = platform-orchestrator_kubernetes_runner.eks_runner[0].id
}

resource "platform-orchestrator_environment_type" "environment_type" {
  id           = "${local.prefix}-development"
  display_name = "Development Environment"
}

resource "platform-orchestrator_project" "project" {
  id         = "${local.prefix}-tutorial"
  depends_on = [
    platform-orchestrator_runner_rule.gke_runner_rule,
    platform-orchestrator_runner_rule.eks_runner_rule
  ]
}

resource "platform-orchestrator_environment" "dev_environment" {
  id               = "dev"
  project_id       = platform-orchestrator_project.project.id
  env_type_id = platform-orchestrator_environment_type.environment_type.id
}

resource "platform-orchestrator_environment" "score_environment" {
  id               = "score"
  project_id       = platform-orchestrator_project.project.id
  env_type_id = platform-orchestrator_environment_type.environment_type.id
}