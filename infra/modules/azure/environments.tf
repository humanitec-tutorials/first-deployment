# Azure-specific Environments
# These environments automatically use the Azure runner

resource "platform-orchestrator_environment" "dev" {
  id          = "azure-dev"
  project_id  = var.project_id
  env_type_id = var.env_type_id

  depends_on = [
    module.runner  # Natural dependency - wait for Azure runner to be ready
  ]
}

resource "platform-orchestrator_environment" "score" {
  id          = "azure-score"
  project_id  = var.project_id
  env_type_id = var.env_type_id

  depends_on = [
    module.runner  # Natural dependency - wait for Azure runner to be ready
  ]
}

# Module rule for ansible_score_workload in Azure environments
resource "platform-orchestrator_module_rule" "ansible_score_workload" {
  module_id  = "ansible-score-workload"  # References module created in root humanitec.tf
  env_id     = platform-orchestrator_environment.score.id
  project_id = var.project_id
}
