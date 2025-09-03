output "service_account_name" {
  description = "The name of the Kubernetes service account."
  value       = kubernetes_service_account.service_account.metadata[0].name
}
