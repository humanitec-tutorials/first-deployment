variable "gcp_project_id" {
  description = "GCP project id"
  type        = string
  default     = "dummy-project"
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "humanitec_org" {
  description = "Humanitec organization name"
}

variable "humanitec_auth_token" {
  description = "Humanitec auth token"
}

variable "prefix" {
  description = "Prefix for resources to allow multiple instances (4 random chars if empty)"
  type        = string
  default     = ""
}

variable "enabled_cloud_providers" {
  description = "List of cloud providers to enable (valid values: 'gcp', 'aws', 'azure')"
  type        = list(string)
  default     = ["gcp"]

  validation {
    condition     = length([for provider in var.enabled_cloud_providers : provider if contains(["gcp", "aws", "azure"], provider)]) == length(var.enabled_cloud_providers)
    error_message = "Valid values for enabled_cloud_providers are 'gcp', 'aws', and 'azure'."
  }
}

# AWS Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Azure Variables
variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "azure_location" {
  description = "Azure region/location"
  type        = string
  default     = "East US"
}

variable "azure_client_id" {
  description = "Azure service principal client ID"
  type        = string
  default     = ""
}

variable "azure_client_secret" {
  description = "Azure service principal client secret"
  type        = string
  default     = ""
  sensitive   = true
}
