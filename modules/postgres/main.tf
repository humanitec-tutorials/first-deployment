terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  required_version = ">= 0.14"
}

resource "random_id" "release" {
  prefix      = "db-"
  byte_length = 5
}

resource "random_password" "pwd" {
  length  = 16
  special = false
  lower   = true
  upper   = true
  numeric = true
}

resource "kubernetes_manifest" "postgres_cluster" {
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = random_id.release.hex
      namespace = var.namespace
    }
    spec = {
      instances = 1
      storage = {
        size = "1Gi"
      }
      bootstrap = {
        initdb = {
          database = "default"
          owner    = "db-user"
          secret = {
            name = kubernetes_secret.postgres_credentials.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_secret" "postgres_credentials" {
  metadata {
    name      = "${random_id.release.hex}-credentials"
    namespace = var.namespace
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = "db-user"
    password = random_password.pwd.result
  }
}