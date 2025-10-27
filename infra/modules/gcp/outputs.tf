output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.cluster.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "service_account_email" {
  description = "Runner service account email"
  value       = google_service_account.runner.email
}

output "runner_id" {
  description = "Humanitec runner ID"
  value       = module.runner.runner_id
}

output "runner_rule_id" {
  description = "Humanitec runner rule ID"
  value       = module.runner.runner_rule_id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
}

output "cnpg_helm_release" {
  description = "CloudNativePG helm release for dependency tracking"
  value       = helm_release.cloudnative_pg.id
}
