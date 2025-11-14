output "cluster_name" {
  description = "Name of the KinD cluster"
  value       = local.create_local ? local.cluster_name : null
}

output "kubeconfig_context" {
  description = "Kubeconfig context name for the KinD cluster"
  value       = local.create_local ? "kind-${local.cluster_name}" : null
}

output "base_domain" {
  description = "Base domain for accessing applications"
  value       = var.base_domain
}

output "ingress_http_url" {
  description = "HTTP URL for accessing applications"
  value       = "http://${var.base_domain}"
}

output "ingress_https_url" {
  description = "HTTPS URL for accessing applications (if configured)"
  value       = "https://${var.base_domain}"
}

output "runner_namespace" {
  description = "Namespace where the Humanitec runner is deployed"
  value       = local.create_local ? kubernetes_namespace.runner.metadata[0].name : null
}

output "environment_id" {
  description = "ID of the local development environment"
  value       = local.create_local ? platform-orchestrator_environment.local_dev.id : null
}
