terraform {
  ## You can activate this if you want to have a remote state storage
  ## for team collaboration or want to keep this infrastructure around longer
  # backend "gcs" {
  #   bucket = "first-deployment-demo"
  #   prefix = "terraform/state"
  # }

  required_providers {
    # Common providers that are always needed
    platform-orchestrator = {
      source  = "humanitec/platform-orchestrator"
      version = ">= 2.9.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.3"
    }

    # Cloud provider-specific providers
    # Only needed if corresponding cloud module is enabled
    # kubernetes and helm are configured in each cloud module
  #   google = {
  #     source  = "hashicorp/google"
  #     version = "~> 6.13"
  #   }

  #   aws = {
  #     source  = "hashicorp/aws"
  #     version = "~> 5.82"
  #   }

  #   azurerm = {
  #     source  = "hashicorp/azurerm"
  #     version = "~> 4.13"
  #   }
  }
}

# Random prefix if not provided
resource "random_string" "prefix" {
  length  = 4
  special = false
  upper   = false
  numeric = false
}

locals {
  prefix = var.prefix != "" ? var.prefix : random_string.prefix.result
}

# provider "google" {
#   project = var.gcp_project_id
#   region  = var.gcp_region
# }

# provider "aws" {
#   region = var.aws_region
# }

# provider "azurerm" {
#   features {}
#   subscription_id = var.azure_subscription_id
#   tenant_id       = var.azure_tenant_id
# }

# Cloud Modules - Enable/disable by commenting/uncommenting
# Each module contains its own kubernetes/helm provider configuration
# To enable multi-cloud: uncomment multiple modules
# To disable a cloud: comment out the entire module block

# Local KinD Module - For local development with KinD (Kubernetes in Docker)
# Requires: Docker and kind CLI installed
# module "local" {
#   source = "./modules/local"

#   prefix               = local.prefix
#   cluster_name         = var.local_cluster_name
#   base_domain          = var.local_base_domain
#   ingress_http_port    = var.local_ingress_http_port
#   ingress_https_port   = var.local_ingress_https_port
#   humanitec_org        = var.humanitec_org
#   humanitec_auth_token = var.humanitec_auth_token
#   public_key_pem       = tls_private_key.agent_runner_key.public_key_pem
#   private_key_pem      = tls_private_key.agent_runner_key.private_key_pem
#   project_id           = platform-orchestrator_project.project.id
#   env_type_id          = platform-orchestrator_environment_type.environment_type.id
# }

# module "gcp" {
#   source = "./modules/gcp"

#   prefix                     = local.prefix
#   gcp_project_id             = var.gcp_project_id
#   gcp_region                 = var.gcp_region
#   gcp_zone                   = var.gcp_zone
#   humanitec_org              = var.humanitec_org
#   humanitec_auth_token       = var.humanitec_auth_token
#   public_key_pem             = tls_private_key.agent_runner_key.public_key_pem
#   private_key_pem            = tls_private_key.agent_runner_key.private_key_pem
#   project_id                 = platform-orchestrator_project.project.id
#   env_type_id                = platform-orchestrator_environment_type.environment_type.id
#   vm_fleet_resource_type_id  = platform-orchestrator_resource_type.vm_fleet.id
# }

# module "aws" {
#   source = "./modules/aws"

#   prefix                     = local.prefix
#   aws_region                 = var.aws_region
#   humanitec_org              = var.humanitec_org
#   humanitec_auth_token       = var.humanitec_auth_token
#   public_key_pem             = tls_private_key.agent_runner_key.public_key_pem
#   private_key_pem            = tls_private_key.agent_runner_key.private_key_pem
#   project_id                 = platform-orchestrator_project.project.id
#   env_type_id                = platform-orchestrator_environment_type.environment_type.id
#   vm_fleet_resource_type_id  = platform-orchestrator_resource_type.vm_fleet.id
# }

# module "azure" {
#   source = "./modules/azure"

#   prefix                     = local.prefix
#   azure_subscription_id      = var.azure_subscription_id
#   azure_tenant_id            = var.azure_tenant_id
#   azure_location             = var.azure_location
#   azure_client_id            = var.azure_client_id
#   azure_client_secret        = var.azure_client_secret
#   humanitec_org              = var.humanitec_org
#   humanitec_auth_token       = var.humanitec_auth_token
#   public_key_pem             = tls_private_key.agent_runner_key.public_key_pem
#   private_key_pem            = tls_private_key.agent_runner_key.private_key_pem
#   project_id                 = platform-orchestrator_project.project.id
#   env_type_id                = platform-orchestrator_environment_type.environment_type.id
#   vm_fleet_resource_type_id  = platform-orchestrator_resource_type.vm_fleet.id
# }

# TLS key for runner authentication
resource "tls_private_key" "agent_runner_key" {
  algorithm = "ED25519"
}
