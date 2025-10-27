# Platform Orchestrator Provider for AWS
resource "platform-orchestrator_provider" "aws" {
  id                 = "default"
  description        = "Provider using mounted credentials for AWS"
  provider_type      = "aws"
  source             = "hashicorp/aws"
  version_constraint = "~> 5.0"
  configuration = jsonencode({
    region                   = var.aws_region
    shared_credentials_files = ["/mnt/aws-creds/credentials"]
  })
}

# VM Fleet Module for AWS
resource "platform-orchestrator_module" "vm_fleet" {
  id            = "vm-fleet-aws"
  resource_type = var.vm_fleet_resource_type_id  # Reference from root to create dependency
  provider_mapping = {
    aws = "aws.default"
  }
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/vm-fleet/aws"

  depends_on = [
    platform-orchestrator_provider.aws  # Ensure AWS provider exists first
  ]
}

resource "platform-orchestrator_module_rule" "vm_fleet" {
  module_id = platform-orchestrator_module.vm_fleet.id

  depends_on = [
    platform-orchestrator_module.vm_fleet
  ]
}
