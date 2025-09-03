terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.3"
    }
  }
}

resource "random_id" "namespace_name" {
  byte_length = 8
}

resource "kubernetes_namespace" "namespace" {
  metadata {
    name = random_id.namespace_name.hex
  }
}
