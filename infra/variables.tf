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
