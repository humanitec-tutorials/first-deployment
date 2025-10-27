# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-first-deployment-rg"
  location = var.azure_location
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-first-deployment-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnet for AKS
resource "azurerm_subnet" "aks" {
  name                 = "${var.prefix}-first-deployment-aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"]
}

# User Assigned Managed Identity for AKS
resource "azurerm_user_assigned_identity" "aks" {
  location            = azurerm_resource_group.main.location
  name                = "${var.prefix}-first-deployment-aks-identity"
  resource_group_name = azurerm_resource_group.main.name
}

# User Assigned Managed Identity for Humanitec Runner
resource "azurerm_user_assigned_identity" "humanitec_runner" {
  location            = azurerm_resource_group.main.location
  name                = "${var.prefix}-first-deployment-runner-identity"
  resource_group_name = azurerm_resource_group.main.name
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "cluster" {
  name                = "${var.prefix}-first-deployment-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.prefix}-first-deployment-aks"

  default_node_pool {
    name           = "default"
    node_count     = 2
    vm_size        = "Standard_D2s_v3"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
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
  scope                = azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Role assignment for Humanitec runner - Contributor on subscription
resource "azurerm_role_assignment" "humanitec_aksmi_contributor" {
  scope                = "/subscriptions/${var.azure_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Role assignment for Humanitec runner - Contributor on subscription
resource "azurerm_role_assignment" "humanitec_runner_contributor" {
  scope                = "/subscriptions/${var.azure_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.humanitec_runner.principal_id
}

# Federated identity credential for Humanitec runner workload identity
resource "azurerm_federated_identity_credential" "humanitec_runner" {
  name                = "${var.prefix}-humanitec-runner-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.humanitec_runner.id
  subject             = "system:serviceaccount:${kubernetes_namespace.runner.metadata[0].name}:${var.prefix}-humanitec-runner-sa-inner"
}

# Data source for Azure client config
data "azurerm_client_config" "current" {}
