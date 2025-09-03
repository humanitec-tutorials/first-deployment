terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
  }
}

resource "random_id" "id" {
  byte_length = 8
}

locals {
  workload_type   = lookup(coalesce(try(var.metadata.annotations, null), {}), "score.canyon.com/workload-type", "Deployment")
  pod_labels      = { app = random_id.id.hex }
  # Create a map of all secret data, keyed by a stable identifier
  all_secret_data = merge(
    { for k, v in kubernetes_secret.env : "env-${k}" => v.data },
    { for k, v in kubernetes_secret.files : "file-${k}" => v.data }
  )

  # Create a sorted list of the keys of the combined secret data
  sorted_secret_keys = sort(keys(local.all_secret_data))

  # Create a stable JSON string from the secret data by using the sorted keys
  stable_secret_json = jsonencode([
    for key in local.sorted_secret_keys : {
      key  = key
      data = local.all_secret_data[key]
    }
  ])

  pod_annotations = merge(
    coalesce(try(var.metadata.annotations, null), {}),
    var.additional_annotations,
    { "checksum/config" = sha256(local.stable_secret_json) }
  )

  create_service = var.service != null && length(coalesce(var.service.ports, {})) > 0

  # Flatten files from all containers into a map for easier iteration.
  # We only care about files with inline content for creating secrets.
  all_files_with_content = {
    for pair in flatten([
      for ckey, cval in var.containers : [
        for fkey, fval in coalesce(cval.files, {}) : {
          ckey      = ckey
          fkey      = fkey
          is_binary = lookup(fval, "binaryContent", null) != null
          data      = coalesce(lookup(fval, "binaryContent", null), lookup(fval, "content", null))
        } if lookup(fval, "content", null) != null || lookup(fval, "binaryContent", null) != null
      ] if cval != null
    ]) : "${pair.ckey}-${substr(sha256(pair.fkey), 0, 10)}" => pair
  }

  # Flatten all external volumes from all containers into a single map,
  # assuming volume mount paths are unique across the pod.
  all_volumes = {
    for pair in flatten([
      for cval in var.containers : [
        for vkey, vval in coalesce(cval.volumes, {}) : {
          key   = vkey
          value = vval
        }
      ] if cval != null
    ]) : pair.key => pair.value
  }
}


resource "kubernetes_secret" "env" {
  for_each = nonsensitive(toset([for k, v in var.containers: k if v.variables != null]))

  metadata {
    name        = "${var.metadata.name}-${each.value}-env"
    namespace   = var.namespace
    annotations = var.additional_annotations
  }

  data = var.containers[each.value].variables
}

resource "kubernetes_secret" "files" {
  for_each = nonsensitive(toset(keys(local.all_files_with_content)))

  metadata {
    name        = "${var.metadata.name}-${each.value}"
    namespace   = var.namespace
    annotations = var.additional_annotations
  }

  data = {
    for k, v in { content = local.all_files_with_content[each.value].data } : k => v if !local.all_files_with_content[each.value].is_binary
  }

  binary_data = {
    for k, v in { content = local.all_files_with_content[each.value].data } : k => v if local.all_files_with_content[each.value].is_binary
  }
}

resource "kubernetes_deployment" "default" {
  count = local.workload_type == "Deployment" ? 1 : 0

  metadata {
    name        = var.metadata.name
    annotations = local.pod_annotations
    labels      = local.pod_labels
    namespace   = var.namespace
  }

  wait_for_rollout = var.wait_for_rollout
  timeouts {
    create = "1m"
    update = "1m"
    delete = "1m"
  }

  spec {

    selector {
      match_labels = local.pod_labels
    }

    template {
      metadata {
        annotations = local.pod_annotations
        labels      = local.pod_labels
      }

      spec {
        service_account_name = var.service_account_name
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        dynamic "container" {
          for_each = var.containers
          iterator = container
          content {
            name    = container.key
            image   = container.value.image
            command = container.value.command
            args    = container.value.args
            dynamic "env_from" {
              for_each = container.value.variables != null ? [1] : []
              content {
                secret_ref {
                  name = kubernetes_secret.env[container.key].metadata[0].name
                }
              }
            }
            security_context {
              allow_privilege_escalation = false
            }
            resources {
              limits = {
                cpu    = try(container.value.resources.limits.cpu, null)
                memory = try(container.value.resources.limits.memory, null)
              }
              requests = {
                cpu    = try(container.value.resources.requests.cpu, null)
                memory = try(container.value.resources.requests.memory, null)
              }
            }
            dynamic "liveness_probe" {
              for_each = container.value.livenessProbe != null ? [1] : []
              content {
                dynamic "http_get" {
                  for_each = container.value.livenessProbe.httpGet != null ? [1] : []
                  content {
                    path   = container.value.livenessProbe.httpGet.path
                    port   = container.value.livenessProbe.httpGet.port
                    host   = lookup(container.value.livenessProbe.httpGet, "host", null)
                    scheme = lookup(container.value.livenessProbe.httpGet, "scheme", null)
                    dynamic "http_header" {
                      for_each = coalesce(container.value.livenessProbe.httpGet.httpHeaders, [])
                      iterator = header
                      content {
                        name  = header.value.name
                        value = header.value.value
                      }
                    }
                  }
                }
                dynamic "exec" {
                  for_each = container.value.livenessProbe.exec != null ? [1] : []
                  content {
                    command = container.value.livenessProbe.exec.command
                  }
                }
              }
            }
            dynamic "readiness_probe" {
              for_each = container.value.readinessProbe != null ? [1] : []
              content {
                dynamic "http_get" {
                  for_each = container.value.readinessProbe.httpGet != null ? [1] : []
                  content {
                    path   = container.value.readinessProbe.httpGet.path
                    port   = container.value.readinessProbe.httpGet.port
                    host   = lookup(container.value.readinessProbe.httpGet, "host", null)
                    scheme = lookup(container.value.readinessProbe.httpGet, "scheme", null)
                    dynamic "http_header" {
                      for_each = coalesce(container.value.readinessProbe.httpGet.httpHeaders, [])
                      iterator = header
                      content {
                        name  = header.value.name
                        value = header.value.value
                      }
                    }
                  }
                }
                dynamic "exec" {
                  for_each = container.value.readinessProbe.exec != null ? [1] : []
                  content {
                    command = container.value.readinessProbe.exec.command
                  }
                }
              }
            }
            dynamic "volume_mount" {
              for_each = { for k, v in local.all_files_with_content : k => v if v.ckey == container.key }
              iterator = file
              content {
                name       = "file-${file.key}"
                mount_path = dirname(file.value.fkey)
                read_only  = true
              }
            }
            dynamic "volume_mount" {
              for_each = coalesce(container.value.volumes, {})
              iterator = volume
              content {
                name       = "volume-${volume.key}"
                mount_path = volume.key
                read_only  = coalesce(volume.value.readOnly, false)
              }
            }
          }
        }
        dynamic "volume" {
          for_each = local.all_files_with_content
          iterator = file
          content {
            name = "file-${file.key}"
            secret {
              secret_name = kubernetes_secret.files[file.key].metadata[0].name
              items {
                key  = "content"
                path = basename(file.value.fkey)
              }
            }
          }
        }
        dynamic "volume" {
          for_each = local.all_volumes
          iterator = volume
          content {
            name = "volume-${volume.key}"
            persistent_volume_claim {
              claim_name = volume.value.source
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "default" {
  count = local.create_service ? 1 : 0

  metadata {
    name        = var.metadata.name
    namespace   = var.namespace
    labels      = local.pod_labels
    annotations = var.additional_annotations
  }

  spec {
    selector = local.pod_labels

    dynamic "port" {
      for_each = coalesce(var.service.ports, {})
      iterator = service_port
      content {
        name        = service_port.key
        port        = service_port.value.port
        target_port = coalesce(service_port.value.targetPort, service_port.value.port)
        protocol    = coalesce(service_port.value.protocol, "TCP")
      }
    }
  }
}

resource "kubernetes_stateful_set" "default" {
  count = local.workload_type == "StatefulSet" ? 1 : 0

  metadata {
    name        = var.metadata.name
    annotations = local.pod_annotations
    labels      = local.pod_labels
    namespace   = var.namespace
  }

  wait_for_rollout = var.wait_for_rollout
  timeouts {
    create = "1m"
    update = "1m"
    delete = "1m"
  }

  spec {
    selector {
      match_labels = local.pod_labels
    }

    service_name = var.metadata.name

    template {
      metadata {
        annotations = local.pod_annotations
        labels      = local.pod_labels
      }

      spec {
        service_account_name = var.service_account_name
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
        dynamic "container" {
          for_each = var.containers
          iterator = container
          content {
            name    = container.key
            image   = container.value.image
            command = container.value.command
            args    = container.value.args
            dynamic "env_from" {
              for_each = container.value.variables != null ? [1] : []
              content {
                secret_ref {
                  name = kubernetes_secret.env[container.key].metadata[0].name
                }
              }
            }
            security_context {
              allow_privilege_escalation = false
            }
            resources {
              limits = {
                cpu    = try(container.value.resources.limits.cpu, null)
                memory = try(container.value.resources.limits.memory, null)
              }
              requests = {
                cpu    = try(container.value.resources.requests.cpu, null)
                memory = try(container.value.resources.requests.memory, null)
              }
            }
            dynamic "liveness_probe" {
              for_each = container.value.livenessProbe != null ? [1] : []
              content {
                dynamic "http_get" {
                  for_each = container.value.livenessProbe.httpGet != null ? [1] : []
                  content {
                    path   = container.value.livenessProbe.httpGet.path
                    port   = container.value.livenessProbe.httpGet.port
                    host   = lookup(container.value.livenessProbe.httpGet, "host", null)
                    scheme = lookup(container.value.livenessProbe.httpGet, "scheme", null)
                    dynamic "http_header" {
                      for_each = coalesce(container.value.livenessProbe.httpGet.httpHeaders, [])
                      iterator = header
                      content {
                        name  = header.value.name
                        value = header.value.value
                      }
                    }
                  }
                }
                dynamic "exec" {
                  for_each = container.value.livenessProbe.exec != null ? [1] : []
                  content {
                    command = container.value.livenessProbe.exec.command
                  }
                }
              }
            }
            dynamic "readiness_probe" {
              for_each = container.value.readinessProbe != null ? [1] : []
              content {
                dynamic "http_get" {
                  for_each = container.value.readinessProbe.httpGet != null ? [1] : []
                  content {
                    path   = container.value.readinessProbe.httpGet.path
                    port   = container.value.readinessProbe.httpGet.port
                    host   = lookup(container.value.readinessProbe.httpGet, "host", null)
                    scheme = lookup(container.value.readinessProbe.httpGet, "scheme", null)
                    dynamic "http_header" {
                      for_each = coalesce(container.value.readinessProbe.httpGet.httpHeaders, [])
                      iterator = header
                      content {
                        name  = header.value.name
                        value = header.value.value
                      }
                    }
                  }
                }
                dynamic "exec" {
                  for_each = container.value.readinessProbe.exec != null ? [1] : []
                  content {
                    command = container.value.readinessProbe.exec.command
                  }
                }
              }
            }
            dynamic "volume_mount" {
              for_each = { for k, v in local.all_files_with_content : k => v if v.ckey == container.key }
              iterator = file
              content {
                name       = "file-${file.key}"
                mount_path = dirname(file.value.fkey)
                read_only  = true
              }
            }
            dynamic "volume_mount" {
              for_each = coalesce(container.value.volumes, {})
              iterator = volume
              content {
                name       = "volume-${volume.key}"
                mount_path = volume.key
                read_only  = coalesce(volume.value.readOnly, false)
              }
            }
          }
        }
        dynamic "volume" {
          for_each = local.all_files_with_content
          iterator = file
          content {
            name = "file-${file.key}"
            secret {
              secret_name = kubernetes_secret.files[file.key].metadata[0].name
              items {
                key  = "content"
                path = basename(file.value.fkey)
              }
            }
          }
        }
        dynamic "volume" {
          for_each = local.all_volumes
          iterator = volume
          content {
            name = "volume-${volume.key}"
            persistent_volume_claim {
              claim_name = volume.value.source
            }
          }
        }
      }
    }
  }
}
