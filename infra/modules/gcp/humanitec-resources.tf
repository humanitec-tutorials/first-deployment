# Platform Orchestrator Provider for Google
resource "platform-orchestrator_provider" "google" {
  id                 = "default"
  description        = "Provider using default runner environment variables for Google"
  provider_type      = "google"
  source             = "hashicorp/google"
  version_constraint = "~> 4.74"
  configuration = jsonencode({
    region      = var.gcp_region
    zone        = var.gcp_zone
    project     = var.gcp_project_id
    credentials = "/providers/google-service-account/credentials.json"
  })
}

# Resource Type: GCS Bucket
resource "platform-orchestrator_resource_type" "bucket" {
  id          = "bucket"
  description = "A bucket in Google Cloud Storage"
  output_schema = jsonencode({
    type = "object"
    properties = {
      name = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true

  depends_on = [platform-orchestrator_provider.google]
}

# Module: GCS Bucket
resource "platform-orchestrator_module" "bucket" {
  id            = "gcs-bucket"
  description   = "Module for a Google Cloud Storage bucket"
  resource_type = platform-orchestrator_resource_type.bucket.id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/bucket"
  provider_mapping = {
    google = "google.default"
  }
  module_inputs = jsonencode({
    google_storage_bucket_name = "${var.prefix}-first-deployment-bucket"
  })

  depends_on = [
    platform-orchestrator_provider.google  # Ensure Google provider exists first
  ]
}

resource "platform-orchestrator_module_rule" "bucket" {
  module_id = platform-orchestrator_module.bucket.id

  depends_on = [
    platform-orchestrator_module.bucket
  ]
}

# Resource Type: Pub/Sub Queue
resource "platform-orchestrator_resource_type" "queue" {
  id          = "queue"
  description = "A queue in Google Cloud Pub/Sub"
  output_schema = jsonencode({
    type = "object"
    properties = {
      name = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true

  depends_on = [platform-orchestrator_provider.google]
}

# Module: Pub/Sub Topic
resource "platform-orchestrator_module" "queue" {
  id            = "pub-sub-topic"
  description   = "Module for a Google Cloud Pub/Sub topic"
  resource_type = platform-orchestrator_resource_type.queue.id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/pub-sub-topic"
  provider_mapping = {
    google = "google.default"
  }
  module_inputs = jsonencode({
    topic_name = "${var.prefix}-first-deployment-topic"
  })
  depends_on = [platform-orchestrator_provider.google]
}

resource "platform-orchestrator_module_rule" "queue" {
  module_id = platform-orchestrator_module.queue.id

  depends_on = [
    platform-orchestrator_module.queue
  ]
}

# Resource Type: K8s Service Account (GCP-specific with workload identity)
resource "platform-orchestrator_resource_type" "k8s_service_account" {
  id          = "k8s-service-account"
  description = "A Kubernetes service account"
  output_schema = jsonencode({
    type = "object"
    properties = {
      service_account_name = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true
  depends_on              = [platform-orchestrator_provider.google]
}

# Module: K8s Service Account (GCP-specific)
# TODO: This module is using a hardcoded GCP service account email, we should create a module and use it here as dependency
resource "platform-orchestrator_module" "k8s_service_account" {
  id            = "k8s-service-account"
  description   = "Module for a Kubernetes service account"
  resource_type = platform-orchestrator_resource_type.k8s_service_account.id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/k8s-service-account"
  provider_mapping = {
    kubernetes = "kubernetes.default"
    google     = "google.default"
  }
  dependencies = {
    namespace = {
      type = "k8s-namespace"
      id   = "main"
    }
  }
  module_inputs = jsonencode({
    gcp_service_account_email = "htc-demo-00@htc-demo-00-gcp.iam.gserviceaccount.com"
    namespace                 = "$${resources.namespace.outputs.namespace}"
    project_id                = var.gcp_project_id
  })

  depends_on = [
    platform-orchestrator_provider.google  # Ensure Google provider exists first
  ]
}

resource "platform-orchestrator_module_rule" "k8s_service_account" {
  module_id = platform-orchestrator_module.k8s_service_account.id

  depends_on = [
    platform-orchestrator_module.k8s_service_account
  ]
}

# VM Fleet Module for GCP
resource "platform-orchestrator_module" "vm_fleet" {
  id            = "vm-fleet-gcp"
  resource_type = var.vm_fleet_resource_type_id  # Reference from root to create dependency
  provider_mapping = {
    google = "google.default"
  }
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/vm-fleet/google"

  depends_on = [
    platform-orchestrator_provider.google  # Ensure Google provider exists first
  ]
}

resource "platform-orchestrator_module_rule" "vm_fleet" {
  module_id = platform-orchestrator_module.vm_fleet.id

  depends_on = [
    platform-orchestrator_module.vm_fleet
  ]
}
