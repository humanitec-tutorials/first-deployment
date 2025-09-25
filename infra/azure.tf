provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  tenant_id      = var.azure_tenant_id
}

# Resource Group
resource "azurerm_resource_group" "main" {
  count = local.create_azure ? 1 : 0

  name     = "${local.prefix}-first-deployment-rg"
  location = var.azure_location
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  count = local.create_azure ? 1 : 0

  name                = "${local.prefix}-first-deployment-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.main[0].location
  resource_group_name = azurerm_resource_group.main[0].name
}

# Subnet for AKS
resource "azurerm_subnet" "aks" {
  count = local.create_azure ? 1 : 0

  name                 = "${local.prefix}-first-deployment-aks-subnet"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.10.1.0/24"]
}

# User Assigned Managed Identity for AKS
resource "azurerm_user_assigned_identity" "aks" {
  count = local.create_azure ? 1 : 0

  location            = azurerm_resource_group.main[0].location
  name                = "${local.prefix}-first-deployment-aks-identity"
  resource_group_name = azurerm_resource_group.main[0].name
}

# User Assigned Managed Identity for Humanitec Runner
resource "azurerm_user_assigned_identity" "humanitec_runner" {
  count = local.create_azure ? 1 : 0

  location            = azurerm_resource_group.main[0].location
  name                = "${local.prefix}-first-deployment-runner-identity"
  resource_group_name = azurerm_resource_group.main[0].name
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "cluster" {
  count = local.create_azure ? 1 : 0

  name                = "${local.prefix}-first-deployment-aks"
  location            = azurerm_resource_group.main[0].location
  resource_group_name = azurerm_resource_group.main[0].name
  dns_prefix          = "${local.prefix}-first-deployment-aks"

  default_node_pool {
    name           = "default"
    node_count     = 2
    vm_size        = "Standard_D2s_v3"
    vnet_subnet_id = azurerm_subnet.aks[0].id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[0].id]
  }

  # Enable workload identity for Humanitec runner authentication
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }
}

# Role assignment for AKS managed identity
resource "azurerm_role_assignment" "aks_network_contributor" {
  count = local.create_azure ? 1 : 0

  scope                = azurerm_subnet.aks[0].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

# Role assignment for Humanitec runner - Contributor on resource group
resource "azurerm_role_assignment" "humanitec_runner_contributor" {
  count = local.create_azure ? 1 : 0

  scope                = azurerm_resource_group.main[0].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.humanitec_runner[0].principal_id
}

# Federated identity credential for Humanitec runner workload identity
resource "azurerm_federated_identity_credential" "humanitec_runner" {
  count = local.create_azure ? 1 : 0

  name                = "${local.prefix}-humanitec-runner-federated-credential"
  resource_group_name = azurerm_resource_group.main[0].name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster[0].oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.humanitec_runner[0].id
  subject             = "system:serviceaccount:${local.prefix}-humanitec-runner:${local.prefix}-humanitec-runner-sa-inner"
}