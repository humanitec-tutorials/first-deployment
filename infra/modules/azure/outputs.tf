output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.cluster.name
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "cluster_endpoint" {
  description = "AKS cluster endpoint"
  value       = azurerm_kubernetes_cluster.cluster.kube_config[0].host
}

output "cluster_ca_certificate" {
  description = "AKS cluster CA certificate"
  value       = azurerm_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "AKS cluster OIDC issuer URL"
  value       = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
}

output "runner_identity_client_id" {
  description = "Humanitec runner managed identity client ID"
  value       = azurerm_user_assigned_identity.humanitec_runner.client_id
}

output "runner_id" {
  description = "Humanitec runner ID"
  value       = module.runner.runner_id
}

output "runner_rule_id" {
  description = "Humanitec runner rule ID"
  value       = module.runner.runner_rule_id
}

output "vnet_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.main.id
}

output "aks_subnet_id" {
  description = "AKS Subnet ID"
  value       = azurerm_subnet.aks.id
}

output "cnpg_helm_release" {
  description = "CloudNativePG helm release for dependency tracking"
  value       = helm_release.cloudnative_pg.id
}
