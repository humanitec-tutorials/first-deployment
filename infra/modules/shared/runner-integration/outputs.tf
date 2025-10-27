output "runner_id" {
  description = "ID of the Humanitec runner"
  value       = platform-orchestrator_kubernetes_agent_runner.agent_runner.id
}

output "runner_rule_id" {
  description = "ID of the runner rule"
  value       = platform-orchestrator_runner_rule.agent_runner_rule.id
}

output "helm_release_name" {
  description = "Name of the Helm release"
  value       = helm_release.humanitec_runner.name
}

output "helm_release_namespace" {
  description = "Namespace of the Helm release"
  value       = helm_release.humanitec_runner.namespace
}
