# Azure-specific kubernetes provider configuration
# This provider connects to the AKS cluster created in this module

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.cluster.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
  
  # Azure can use either token or client certificates
  client_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_certificate)
  client_key         = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_key)
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.cluster.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)

    # Azure can use either token or client certificates
    client_certificate = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_certificate)
    client_key         = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_key)
  }
}
