resource "platform-orchestrator_provider" "google" {
  count = local.create_gcp ? 1 : 0

  id                 = "default"
  description        = "Provider using default runner environment variables for Google"
  provider_type      = "google"
  source             = "hashicorp/google"
  version_constraint = "~> 4.74"
  configuration = jsonencode({
    region      = var.gcp_region
    zone        = var.gcp_zone
    project     = var.gcp_project_id
    credentials = "/providers/google-service-account/credentials.json"
  })
}

resource "platform-orchestrator_provider" "aws" {
  count = local.create_aws ? 1 : 0

  id                 = "default"
  description        = "Provider using default runner environment variables for AWS"
  provider_type      = "aws"
  source             = "hashicorp/aws"
  version_constraint = "~> 5.0"
  configuration = jsonencode({
    region = var.aws_region
  })
}

resource "platform-orchestrator_resource_type" "bucket" {
  count = local.create_gcp ? 1 : 0

  id          = "bucket"
  description = "A bucket in Google Cloud Storage"
  output_schema = jsonencode({
    type = "object"
    properties = {
      name = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true

  depends_on = [ platform-orchestrator_provider.google ]
}

resource "platform-orchestrator_module" "bucket" {
  count = local.create_gcp ? 1 : 0

  id            = "gcs-bucket"
  description   = "Module for a Google Cloud Storage bucket"
  resource_type = platform-orchestrator_resource_type.bucket[0].id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/bucket"
  provider_mapping = {
    google = "google.default"
  }
  module_inputs = jsonencode({
    google_storage_bucket_name = "${local.prefix}-first-deployment-bucket"
  })
}

resource "platform-orchestrator_module_rule" "bucket" {
  count = local.create_gcp ? 1 : 0

  module_id = platform-orchestrator_module.bucket[0].id
}

resource "platform-orchestrator_resource_type" "queue" {
  count = local.create_gcp ? 1 : 0

  id          = "queue"
  description = "A queue in Google Cloud Pub/Sub"
  output_schema = jsonencode({
    type = "object"
    properties = {
      name = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true

  depends_on = [ platform-orchestrator_provider.google ]
}

resource "platform-orchestrator_module" "queue" {
  count = local.create_gcp ? 1 : 0

  id            = "pub-sub-topic"
  description   = "Module for a Google Cloud Pub/Sub topic"
  resource_type = platform-orchestrator_resource_type.queue[0].id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/pub-sub-topic"
  provider_mapping = {
    google = "google.default"
  }
  module_inputs = jsonencode({
    topic_name = "${local.prefix}-first-deployment-topic"
  })
  depends_on = [platform-orchestrator_provider.google]
}

resource "platform-orchestrator_module_rule" "queue" {
  count = local.create_gcp ? 1 : 0

  module_id = platform-orchestrator_module.queue[0].id
}

resource "platform-orchestrator_provider" "k8s" {
  id                 = "default"
  description        = "Provider using default runner environment variables for Kubernetes"
  provider_type      = "kubernetes"
  source             = "hashicorp/kubernetes"
  version_constraint = "~> 2.38.0"
  configuration      = jsonencode({})
}

resource "platform-orchestrator_resource_type" "k8s-namespace" {
  id          = "k8s-namespace"
  description = "A Kubernetes namespace"
  output_schema = jsonencode({
    type = "object"
    properties = {
      namespace = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true
  depends_on = [ platform-orchestrator_provider.k8s ]
}

resource "platform-orchestrator_module" "k8s-namespace" {
  id            = "k8s-namespace"
  description   = "Module for a Kubernetes namespace"
  resource_type = platform-orchestrator_resource_type.k8s-namespace.id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/k8s-namespace"
  provider_mapping = {
    kubernetes = "kubernetes.default"
  }
}

resource "platform-orchestrator_module_rule" "k8s-namespace" {
  module_id = platform-orchestrator_module.k8s-namespace.id
}

resource "platform-orchestrator_resource_type" "k8s-service-account" {
  id          = "k8s-service-account"
  description = "A Kubernetes service account"
  output_schema = jsonencode({
    type = "object"
    properties = {
      service_account_name = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true
  depends_on = [ platform-orchestrator_provider.k8s ]
}

# TODO: This module is using a hardcoded GCP service account email, we should create a module and use it here as dependency
resource "platform-orchestrator_module" "k8s-service-account" {
  count = local.create_gcp ? 1 : 0

  id            = "k8s-service-account"
  description   = "Module for a Kubernetes service account"
  resource_type = platform-orchestrator_resource_type.k8s-service-account.id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/k8s-service-account"
  provider_mapping = {
    kubernetes = "kubernetes.default"
    google = "google.default"
  }
  dependencies = {
    namespace = {
      type = platform-orchestrator_resource_type.k8s-namespace.id
      id   = "main"
    }
  }
  module_inputs = jsonencode({
    gcp_service_account_email = "htc-demo-00@htc-demo-00-gcp.iam.gserviceaccount.com"
    namespace                 = "$${resources.namespace.outputs.namespace}"
    project_id                = var.gcp_project_id
  })
}

resource "platform-orchestrator_module_rule" "k8s-service-account" {
  count = local.create_gcp ? 1 : 0

  module_id = platform-orchestrator_module.k8s-service-account[0].id
}

resource "platform-orchestrator_resource_type" "in-cluster-postgres" {
  id          = "postgres"
  description = "An in-cluster Postgres database"
  output_schema = jsonencode({
    type = "object"
    properties = {
      hostname = {
        type = "string"
      }
      port = {
        type = "integer"
      }
      database = {
        type = "string"
      }
      username = {
        type = "string"
      }
      password = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true
  depends_on = [ platform-orchestrator_provider.k8s ]
}

resource "platform-orchestrator_provider" "helm" {
  id                 = "default"
  description        = "Provider using default runner environment variables for Helm"
  provider_type      = "helm"
  source             = "hashicorp/helm"
  version_constraint = "~> 3.0.2"
  configuration      = jsonencode({})
}

resource "platform-orchestrator_resource_type" "score-workload" {
  id          = "score-workload"
  description = "A workload that deploys a Score files"
  output_schema = jsonencode({
    type = "object"
    properties = {
      loadbalancer = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true
  depends_on = [ platform-orchestrator_provider.helm, platform-orchestrator_provider.ansibleplay ]
}

resource "platform-orchestrator_provider" "ansibleplay" {
  id                 = "default"
  description        = "Humanitec provider for Ansible playbooks"
  provider_type      = "ansibleplay"
  source             = "humanitec/ansibleplay"
  version_constraint = "~> 0.3.2"
  configuration      = jsonencode({})
}

resource "platform-orchestrator_resource_type" "vm-fleet" {
  count = local.create_gcp || local.create_aws ? 1 : 0

  id          = "vm-fleet"
  description = "A fleet of virtual machines"
  output_schema = jsonencode({
    type = "object"
    properties = {
      instance_ips = {
        type = "array"
        items = {
          type = "string"
        }
      }
      ssh_username = {
        type = "string"
      }
      ssh_private_key = {
        type = "string"
      }
      loadbalancer_ip = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true
  depends_on = [ 
    platform-orchestrator_provider.google,
    platform-orchestrator_provider.aws
  ]
}
resource "platform-orchestrator_module" "vm_fleet_example" {
  count = local.create_gcp ? 1 : 0

  id = "vm-fleet-example"
  resource_type = platform-orchestrator_resource_type.vm-fleet[0].id
  provider_mapping = {
    google = "google.default"
  }
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/vm-fleet/google"
}

resource "platform-orchestrator_module_rule" "vm_fleet_example" {
  count = local.create_gcp ? 1 : 0

  module_id = platform-orchestrator_module.vm_fleet_example[0].id
}

# AWS VM Fleet Module
resource "platform-orchestrator_module" "vm_fleet_aws" {
  count = local.create_aws ? 1 : 0

  id = "vm-fleet-aws"
  resource_type = platform-orchestrator_resource_type.vm-fleet[0].id
  provider_mapping = {
    aws = "aws.default"
  }
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/vm-fleet/aws?awsVMs"
}

resource "platform-orchestrator_module_rule" "vm_fleet_aws" {
  count = local.create_aws ? 1 : 0

  module_id = platform-orchestrator_module.vm_fleet_aws[0].id
}

resource "platform-orchestrator_module" "ansible_score_workload" {
  count = local.create_gcp || local.create_aws ? 1 : 0

  id = "ansible-score-workload"
  resource_type = platform-orchestrator_resource_type.score-workload.id
  provider_mapping = {
    ansibleplay = "ansibleplay.default"
  }
  dependencies = {
    fleet = {
      type = platform-orchestrator_resource_type.vm-fleet[0].id
    }
  }
  module_params = {
    metadata = {
      type        = "map"
      description = "The metadata component of the Score workload"
    }
    containers = {
      type        = "map"
      description = "The containers component of the Score workload"
    }
    service = {
      type        = "map"
      is_optional = true
      description = "The service component of the Score workload"
    }
  }
  module_inputs = jsonencode({
    ips = "$${resources.fleet.outputs.instance_ips}"
    loadbalancer = "$${resources.fleet.outputs.loadbalancer_ip}"
    ssh_user = "$${resources.fleet.outputs.ssh_username}"
    ssh_private_key = "$${resources.fleet.outputs.ssh_private_key}"
  })
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/score-workload/ansible"
}

resource "platform-orchestrator_module_rule" "ansible_score_workload" {
  count = local.create_gcp || local.create_aws ? 1 : 0

  module_id = platform-orchestrator_module.ansible_score_workload[0].id
  env_id = platform-orchestrator_environment.score_environment.id
  project_id = platform-orchestrator_project.project.id
}

resource "platform-orchestrator_module" "in-cluster-postgres" {
  id = "in-cluster-postgres"
  resource_type = platform-orchestrator_resource_type.in-cluster-postgres.id
  provider_mapping = {
    helm = "helm.default"
  }
  module_source = "inline"
  module_source_code = <<EOF
terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }

  required_version = ">= 0.14"
}

resource "random_id" "release" {
  prefix = "db-"
  byte_length = "5"
}

resource "random_password" "pwd" {
  length = 16
  special = true
}

resource "helm_release" "db" {
  name = random_id.release.hex
  namespace = "default"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart = "postgresql"
  version = "16.7.18"
  set = [
    { name = "auth.database", value = "default"},
    { name = "auth.username", value = "db-user" },
    { name = "auth.password", value = random_password.pwd.result },
  ]
  wait = true
}

output "hostname" {
  value = "$${random_id.release.hex}-postgresql.default.svc.cluster.local"
}

output "port" {
  value = 5432
}

output "database" {
  value = "default"
}

output "username" {
  value = "db-user"
}

output "password" {
  value = random_password.pwd.result
  sensitive = true
}
EOF
}

resource "platform-orchestrator_module_rule" "in-cluster-postgres" {
  module_id = platform-orchestrator_module.in-cluster-postgres.id
}


resource "platform-orchestrator_module" "score-k8s" {
  id = "score-k8s"
  resource_type = platform-orchestrator_resource_type.score-workload.id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/score-workload/kubernetes"
  module_params = {
    metadata = {
      type        = "map"
      description = "The metadata component of the Score workload"
    }
    containers = {
      type        = "map"
      description = "The containers component of the Score workload"
    }
    service = {
      type        = "map"
      is_optional = true
      description = "The service component of the Score workload"
    }
  }
  provider_mapping = {
    kubernetes = "kubernetes.default"
  }
  module_inputs = jsonencode({
    namespace = "$${resources.ns.outputs.namespace}"
  })
  dependencies = {
    ns = {
      type = platform-orchestrator_resource_type.k8s-namespace.id
    }
  }
}

resource "platform-orchestrator_module_rule" "score-k8s" {
  module_id = platform-orchestrator_module.score-k8s.id
}
