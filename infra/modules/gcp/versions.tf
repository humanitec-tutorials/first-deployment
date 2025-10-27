terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    platform-orchestrator = {
      source  = "humanitec/platform-orchestrator"
      version = ">= 2.9.1"
    }
  }
}
