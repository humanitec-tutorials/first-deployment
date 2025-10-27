variable "enabled" {
  description = "Whether to create GCP resources"
  type        = bool
  default     = true
}

variable "prefix" {
  description = "Prefix for resources"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project id"
  type        = string
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
  type        = string
}

variable "humanitec_auth_token" {
  description = "Humanitec auth token"
  type        = string
  sensitive   = true
}

variable "public_key_pem" {
  description = "Public key PEM for Humanitec API runner registration"
  type        = string
  sensitive   = true
}

variable "private_key_pem" {
  description = "Private key PEM for runner pod authentication"
  type        = string
  sensitive   = true
}

variable "project_id" {
  description = "Humanitec project ID"
  type        = string
}

variable "env_type_id" {
  description = "Humanitec environment type ID"
  type        = string
}

variable "vm_fleet_resource_type_id" {
  description = "VM Fleet resource type ID (from root module)"
  type        = string
}
