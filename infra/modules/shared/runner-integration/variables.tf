variable "prefix" {
  description = "Prefix for runner resources"
  type        = string
}

variable "humanitec_org" {
  description = "Humanitec organization ID"
  type        = string
}

variable "runner_namespace" {
  description = "Kubernetes namespace for the runner"
  type        = string
}

variable "runner_service_account_name" {
  description = "Name of the runner service account"
  type        = string
}

variable "runner_inner_service_account_name" {
  description = "Name of the inner runner service account"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider (gcp, aws, azure)"
  type        = string
  validation {
    condition     = contains(["gcp", "aws", "azure"], var.cloud_provider)
    error_message = "cloud_provider must be one of: gcp, aws, azure"
  }
}

# Cloud-specific configurations
variable "aws_iam_role_arn" {
  description = "AWS IAM role ARN for IRSA (only for AWS)"
  type        = string
  default     = null
}

variable "azure_client_id" {
  description = "Azure managed identity client ID (only for Azure)"
  type        = string
  default     = null
}

variable "azure_tenant_id" {
  description = "Azure tenant ID (only for Azure)"
  type        = string
  default     = null
}

variable "azure_subscription_id" {
  description = "Azure subscription ID (only for Azure)"
  type        = string
  default     = null
}

# Secrets and volume mounts
variable "aws_credentials_secret_name" {
  description = "Name of the AWS credentials secret (only for AWS)"
  type        = string
  default     = null
}

variable "gcp_service_account_secret_name" {
  description = "Name of the GCP service account secret (only for GCP)"
  type        = string
  default     = null
}

variable "public_key_pem" {
  description = "Public key PEM for Humanitec API runner registration (ED25519)"
  type        = string
  sensitive   = true
}

variable "private_key_pem" {
  description = "Private key PEM for runner pod authentication (ED25519)"
  type        = string
  sensitive   = true
}
