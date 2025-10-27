# Platform Orchestrator Provider for Azure
resource "platform-orchestrator_provider" "azurerm" {
  id                 = "default"
  description        = "Provider for Azure using service principal or managed identity"
  provider_type      = "azurerm"
  source             = "hashicorp/azurerm"
  version_constraint = "~> 4.46"
  configuration = jsonencode(merge(
    {
      "features[0]"   = {}
      subscription_id = var.azure_subscription_id
      tenant_id       = var.azure_tenant_id
    },
    var.azure_client_id != "" ? {
      client_id     = var.azure_client_id
      client_secret = var.azure_client_secret
    } : {
      use_cli                   = false
      use_aks_workload_identity = true
    }
  ))
}

# VM Fleet Module for Azure
resource "platform-orchestrator_module" "vm_fleet" {
  id            = "vm-fleet-azure"
  resource_type = var.vm_fleet_resource_type_id  # Reference from root to create dependency
  provider_mapping = {
    azurerm = "azurerm.default"
  }
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/vm-fleet/azure"

  depends_on = [
    platform-orchestrator_provider.azurerm  # Ensure Azure provider exists first
  ]
}

resource "platform-orchestrator_module_rule" "vm_fleet" {
  module_id = platform-orchestrator_module.vm_fleet.id

  depends_on = [
    platform-orchestrator_module.vm_fleet
  ]
}
