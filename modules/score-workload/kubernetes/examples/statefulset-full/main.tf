module "score_workload" {
  source = "../../"

  namespace = "default"

  metadata = {
    name = "statefulset-full"
    annotations = {
      "score.canyon.com/workload-type" = "StatefulSet"
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
      files = {
        "/mnt/test.txt" = {
          content = "hello world"
        }
        "/etc/other.txt" = {
          binaryContent = "Zml6emJ1enoK"
        }
      }
      livenessProbe = {
        httpGet = {
          path = "/"
          port = 80
        }
      }
      readinessProbe = {
        httpGet = {
          path = "/"
          port = 80
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
