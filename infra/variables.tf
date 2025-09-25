variable "gcp_project_id" {
  description = "GCP project id"
}

variable "gcp_region" {
  description = "GCP region"
}

variable "gcp_zone" {
  description = "GCP zone"
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
}

# Azure Variables
variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
}

variable "azure_location" {
  description = "Azure region/location"
  type        = string
}
