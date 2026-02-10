terraform {
  required_version = ">= 1.0"

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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.3"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}
