# Common Outputs
output "prefix" {
  description = "Resource prefix used across all resources"
  value       = local.prefix
}

output "humanitec_org" {
  description = "Humanitec organization ID"
  value       = var.humanitec_org
}

output "project_id" {
  description = "Humanitec project ID"
  value       = platform-orchestrator_project.project.id
}
