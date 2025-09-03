terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.3"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

resource "random_id" "service_account_name" {
  byte_length = 8
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name = random_id.service_account_name.hex
    namespace = var.namespace

    annotations = {
      "iam.gke.io/gcp-service-account" = var.gcp_service_account_email
    }
  }
}

# Enable Workload Identity binding between K8s SA and GCP SA
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.gcp_service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${kubernetes_service_account.service_account.metadata[0].name}]"
}
