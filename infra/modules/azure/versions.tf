terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.13"
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
