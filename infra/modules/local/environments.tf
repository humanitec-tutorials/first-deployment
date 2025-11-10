# Local Development Environment
resource "platform-orchestrator_environment" "local_dev" {
  id           = "${var.prefix}-local-dev"
  project_id   = var.project_id
  env_type_id  = var.env_type_id
  display_name = "Local Development (KinD)"

  depends_on = [module.runner]
}
