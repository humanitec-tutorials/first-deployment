terraform {
  ## You can activate this if you want to have a remote state storage 
  ## for team collaboration or want to keep this infrastructure around longer
  # backend "gcs" {
  #   bucket = "first-deployment-demo"
  #   prefix = "terraform/state"
  # }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.74.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }

    platform-orchestrator = {
      source  = "humanitec/platform-orchestrator"
      version = "2.1.0"
    }
  }

  required_version = ">= 0.14"
}
