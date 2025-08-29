provider "platform-orchestrator" {
  org_id     = var.humanitec_org
  auth_token = var.humanitec_auth_token
  api_url    = "https://api.humanitec.dev"
}

resource "google_service_account_key" "runner_key" {
  service_account_id = google_service_account.runner.name
}

resource "kubernetes_secret" "google_service_account" {
  metadata {
    name      = "google-service-account"
    namespace = kubernetes_namespace.runner.metadata[0].name
  }

  type = "Opaque"

  data = {
    "credentials.json" = base64decode(google_service_account_key.runner_key.private_key)
  }
}

resource "platform-orchestrator_kubernetes_gke_runner" "runner" {
  id          = "first-deployment-gke-runner"
  description = "GKE runner for Humanitec Orchestrator to launch runners in all environments"

  runner_configuration = {
    cluster = {
      name        = google_container_cluster.cluster.name
      project_id  = var.gcp_project_id
      location    = var.gcp_region
      internal_ip = false
      auth = {
        gcp_audience        = "//iam.googleapis.com/projects/${data.google_project.project.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.wip.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.wip_provider.workload_identity_pool_provider_id}"
        gcp_service_account = google_service_account.runner.email
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
                runAsUser = 0,
                runAsGroup = 0
              }
            }
          ]
          volumes = [
            {
              name = "google-service-account"
              secret = {
                secretName = kubernetes_secret.google_service_account.metadata[0].name
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

resource "platform-orchestrator_runner_rule" "runner_rule" {
  runner_id = platform-orchestrator_kubernetes_gke_runner.runner.id
}

resource "platform-orchestrator_environment_type" "environment_type" {
  id           = "development"
  display_name = "Development Environment"
}
