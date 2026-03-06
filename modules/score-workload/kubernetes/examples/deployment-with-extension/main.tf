module "score_workload" {
  source = "../../"

  namespace = "default"

  metadata = {
    name = "deployment-with-extension"
    annotations = {
      "score.canyon.com/workload-type" = "Deployment"
    }
    "score.humanitec.com/extension" = {
      deployment = {
        metadata = {
          annotations = {
            "my-annotation" = "my-value"
          }
          labels = {
            "my-label" = "my-value"
          }
        }
        replicas        = 2
        minReadySeconds = 10
        strategy = {
          type = "RollingUpdate"
          rollingUpdate = {
            maxSurge       = "30%"
            maxUnavailable = "0"
          }
        }
      }
      pod = {
        metadata = {
          annotations = {
            "prometheus.io/scrape" = "true"
          }
        }
        nodeSelector = {
          "topology.kubernetes.io/region" = "europe-west3"
        }
        tolerations = [
          {
            key      = "dedicated"
            operator = "Equal"
            value    = "gpu"
            effect   = "NoSchedule"
          }
        ]
      }
    }
  }

  containers = {
    "main" = {
      image = "nginx:latest"
      variables = {
        "MY_ENV_VAR" = "my-value"
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    }
  }

  service = {
    ports = {
      "http" = {
        port        = 80
        target_port = 80
      }
    }
  }
}
