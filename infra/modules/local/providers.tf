# Local KinD kubernetes provider configuration
# Uses local kubeconfig with KinD context

locals {
  kind_context    = "kind-${local.cluster_name}"
  kubeconfig_path = pathexpand("~/.kube/config")
}

provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = local.kind_context
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path
    config_context = local.kind_context
  }
}
