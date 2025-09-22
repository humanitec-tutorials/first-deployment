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

    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38.0"
    }

    platform-orchestrator = {
      source  = "humanitec/platform-orchestrator"
      version = ">= 2.8.2"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  required_version = ">= 0.14"
}

resource "random_string" "prefix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = false
  special = false
}

locals {
  prefix = var.prefix != "" ? var.prefix : random_string.prefix.result
}
