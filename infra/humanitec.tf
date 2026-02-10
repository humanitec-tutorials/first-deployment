# Humanitec Platform Orchestrator Provider
provider "platform-orchestrator" {
  org_id     = var.humanitec_org
  auth_token = var.humanitec_auth_token
  api_url    = "https://api.humanitec.dev"
}

# Shared Kubernetes Provider (cloud-agnostic)
resource "platform-orchestrator_provider" "k8s" {
  id                 = "default"
  description        = "Provider using default runner environment variables for Kubernetes"
  provider_type      = "kubernetes"
  source             = "hashicorp/kubernetes"
  version_constraint = "~> 2.38.0"
  configuration      = jsonencode({})
}

# Shared Helm Provider (cloud-agnostic)
resource "platform-orchestrator_provider" "helm" {
  id                 = "default"
  description        = "Provider using default runner environment variables for Helm"
  provider_type      = "helm"
  source             = "hashicorp/helm"
  version_constraint = "~> 3.0.2"
  configuration      = jsonencode({})
}

# Shared Ansible Provider (cloud-agnostic)
resource "platform-orchestrator_provider" "ansibleplay" {
  id                 = "default"
  description        = "Humanitec provider for Ansible playbooks"
  provider_type      = "ansibleplay"
  source             = "humanitec/ansibleplay"
  version_constraint = "~> 0.3.2"
  configuration      = jsonencode({})
}

# Shared Resource Type: K8s Namespace (cloud-agnostic)
resource "platform-orchestrator_resource_type" "k8s_namespace" {
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
  depends_on              = [platform-orchestrator_provider.k8s]
}

resource "platform-orchestrator_module" "k8s_namespace" {
  id            = "k8s-namespace"
  description   = "Module for a Kubernetes namespace"
  resource_type = platform-orchestrator_resource_type.k8s_namespace.id
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/k8s-namespace"
  provider_mapping = {
    kubernetes = "kubernetes.default"
  }
}

resource "platform-orchestrator_module_rule" "k8s_namespace" {
  module_id = platform-orchestrator_module.k8s_namespace.id
}

# Shared Resource Type: In-Cluster Postgres (cloud-agnostic)
resource "platform-orchestrator_resource_type" "in_cluster_postgres" {
  id          = "postgres"
  description = "An in-cluster Postgres database using CloudNativePG"
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
  depends_on              = [platform-orchestrator_provider.k8s]
}

resource "platform-orchestrator_module" "in_cluster_postgres" {
  id            = "in-cluster-postgres"
  resource_type = platform-orchestrator_resource_type.in_cluster_postgres.id
  provider_mapping = {
    kubernetes = "kubernetes.default"
  }
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/postgres"
  module_inputs = jsonencode({
    namespace = "$${resources.namespace.outputs.namespace}"
  })
  dependencies = {
    namespace = {
      type = platform-orchestrator_resource_type.k8s_namespace.id
      id   = "main"
    }
  }

  depends_on = [
    platform-orchestrator_provider.k8s
  ]
}

resource "platform-orchestrator_module_rule" "in_cluster_postgres" {
  module_id = platform-orchestrator_module.in_cluster_postgres.id
}

# Shared Resource Type: Score Workload
resource "platform-orchestrator_resource_type" "score_workload" {
  id          = "score-workload"
  description = "A workload that deploys a Score file"
  output_schema = jsonencode({
    type = "object"
    properties = {
      loadbalancer = {
        type = "string"
      }
    }
  })
  is_developer_accessible = true
  depends_on              = [platform-orchestrator_provider.helm, platform-orchestrator_provider.ansibleplay]
}

# Score Workload Module for Kubernetes
resource "platform-orchestrator_module" "score_k8s" {
  id            = "score-k8s"
  resource_type = platform-orchestrator_resource_type.score_workload.id
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
      type = platform-orchestrator_resource_type.k8s_namespace.id
      id   = "main"
    }
  }
}

resource "platform-orchestrator_module_rule" "score_k8s" {
  module_id = platform-orchestrator_module.score_k8s.id
}

# VM Fleet Resource Type
resource "platform-orchestrator_resource_type" "vm_fleet" {
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
}

# Ansible Score Workload Module (for VM-based deployments)
resource "platform-orchestrator_module" "ansible_score_workload" {
  id            = "ansible-score-workload"
  resource_type = platform-orchestrator_resource_type.score_workload.id
  provider_mapping = {
    ansibleplay = "ansibleplay.default"
  }
  dependencies = {
    fleet = {
      type = platform-orchestrator_resource_type.vm_fleet.id
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
    ips             = "$${resources.fleet.outputs.instance_ips}"
    loadbalancer    = "$${resources.fleet.outputs.loadbalancer_ip}"
    ssh_user        = "$${resources.fleet.outputs.ssh_username}"
    ssh_private_key = "$${resources.fleet.outputs.ssh_private_key}"
  })
  module_source = "git::https://github.com/humanitec-tutorials/first-deployment//modules/score-workload/ansible"
}

# Environment Type
resource "platform-orchestrator_environment_type" "environment_type" {
  id           = "${local.prefix}-development"
  display_name = "Development Environment"
}

# Project
resource "platform-orchestrator_project" "project" {
  id = "${local.prefix}-tutorial"
}

resource "platform-orchestrator_resource_type" "route_type" {
  id                      = "route"
  description             = "HTTP route resource type"
  is_developer_accessible = "true"
  output_schema = jsonencode({
    "type" : "object",
    "properties" : {}
  })
}

resource "platform-orchestrator_module" "route" {
  id            = "http-route"
  resource_type = platform-orchestrator_resource_type.route_type.id
  module_source = "git::https://github.com/humanitec-tf-modules/route-kubernetes-http-route"
  depends_on = [ platform-orchestrator_provider.k8s ]
  provider_mapping = {
    kubernetes = "kubernetes.default"
  }
  dependencies = {
    ns = {
      type = platform-orchestrator_resource_type.k8s_namespace.id
      id   = "main"
    }
  }
  module_inputs = jsonencode({
    namespace         = "$${resources.ns.outputs.namespace}"
    gateways          = ["default-gateway"]
    gateway_namespace = "envoy-gateway-system"
  })
  module_params = {
    hostname = {
      type = "string"
    }
    path = {
      type = "string"
    }
    service = {
      type = "string"
    }
    service_port = {
      type = "number"
    }
  }
}

resource "platform-orchestrator_module_rule" "route_module_rule" {
  module_id = platform-orchestrator_module.route.id
}
