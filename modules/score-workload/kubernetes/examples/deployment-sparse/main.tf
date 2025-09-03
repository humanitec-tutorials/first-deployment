module "score_workload" {
  source = "../../"

  namespace = "default"

  metadata = {
    name = "deployment-sparse"
    annotations = {
      "score.canyon.com/workload-type" = "Deployment"
    }
  }

  containers = {
    "main" = {
      image = "nginx:latest"
    }
  }
}
