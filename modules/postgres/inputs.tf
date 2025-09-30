variable "namespace" {
  description = "Kubernetes namespace where the PostgreSQL cluster will be deployed"
  type        = string
  default     = "default"
}