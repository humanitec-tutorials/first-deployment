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
    deepmerge = {
      source  = "isometry/deepmerge"
      version = ">= 0.2.0"
    }
  }
}

resource "random_id" "id" {
  byte_length = 8
}

locals {
  workload_type = lookup(coalesce(try(var.metadata.annotations, null), {}), "score.canyon.com/workload-type", "Deployment")
  pod_labels    = { app = random_id.id.hex }
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
    { "checksum/config" = nonsensitive(sha256(local.stable_secret_json)) }
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

  # --- Extension extraction ---
  extension      = try(var.metadata["score.humanitec.com/extension"], {})
  ext_deployment = try(local.extension.deployment, {})
  ext_pod        = try(local.extension.pod, {})

  ext_deployment_patch = {
    for k, v in {
      metadata = try(local.ext_deployment.metadata, {})
      spec     = { for x, y in local.ext_deployment : x => y if x != "metadata" }
    } : k => v if length(local.ext_deployment) > 0
  }

  ext_pod_patch = {
    for k, v in {
      spec = {
        template = {
          for x, y in {
            metadata = try(local.ext_pod.metadata, {})
            spec     = { for z, w in local.ext_pod : z => w if z != "metadata" }
          } : x => y if length(local.ext_pod) > 0
        }
      }
    } : k => v if length(local.ext_pod) > 0
  }

  # --- Build containers as K8s API JSON ---
  containers = [
    for ckey, cval in var.containers : {
      for k, v in {
        name            = ckey
        image           = cval.image
        command         = cval.command
        args            = cval.args
        securityContext = { allowPrivilegeEscalation = false }

        envFrom = cval.variables != null ? [{ secretRef = { name = kubernetes_secret.env[ckey].metadata[0].name } }] : null

        resources = cval.resources != null ? {
          for rk, rv in {
            limits   = cval.resources.limits != null ? { for lk, lv in cval.resources.limits : lk => lv if lv != null } : null
            requests = cval.resources.requests != null ? { for lk, lv in cval.resources.requests : lk => lv if lv != null } : null
          } : rk => rv if rv != null && rv != {}
        } : null

        livenessProbe = cval.livenessProbe != null ? {
          for pk, pv in {
            httpGet = cval.livenessProbe.httpGet != null ? { for hk, hv in cval.livenessProbe.httpGet : hk => hv if hv != null && hv != [] } : null
            exec    = cval.livenessProbe.exec != null ? { for hk, hv in cval.livenessProbe.exec : hk => hv if hv != null } : null
          } : pk => pv if pv != null && pv != {}
        } : null

        readinessProbe = cval.readinessProbe != null ? {
          for pk, pv in {
            httpGet = cval.readinessProbe.httpGet != null ? { for hk, hv in cval.readinessProbe.httpGet : hk => hv if hv != null && hv != [] } : null
            exec    = cval.readinessProbe.exec != null ? { for hk, hv in cval.readinessProbe.exec : hk => hv if hv != null } : null
          } : pk => pv if pv != null && pv != {}
        } : null

        volumeMounts = length(local.all_files_with_content) > 0 || length(coalesce(cval.volumes, {})) > 0 ? concat(
          [for fk, fv in local.all_files_with_content : { name = "file-${fk}", mountPath = dirname(fv.fkey), readOnly = true } if fv.ckey == ckey],
          [for vkey, vval in coalesce(cval.volumes, {}) : { name = "volume-${vkey}", mountPath = vkey, readOnly = coalesce(vval.readOnly, false) }]
        ) : null
      } : k => v if v != null && v != {} && v != []
    }
  ]

  # --- Build volumes as K8s API JSON ---
  all_pod_volumes = concat(
    [
      for fk, fv in local.all_files_with_content : {
        name = "file-${fk}"
        secret = {
          secretName = kubernetes_secret.files[fk].metadata[0].name
          items      = [{ key = "content", path = basename(fv.fkey) }]
        }
      }
    ],
    [
      for vkey, vval in local.all_volumes : {
        name                  = "volume-${vkey}"
        persistentVolumeClaim = { claimName = vval.source }
      }
    ]
  )

  # --- Build the base manifest ---
  base_manifest = {
    apiVersion = "apps/v1"
    kind       = local.workload_type
    metadata = {
      name        = var.metadata.name
      namespace   = var.namespace
      annotations = local.pod_annotations
      labels      = local.pod_labels
    }
    spec = merge(
      {
        selector = {
          matchLabels = local.pod_labels
        }
        template = {
          metadata = {
            annotations = local.pod_annotations
            labels      = local.pod_labels
          }
          spec = merge(
            {
              securityContext = {
                runAsNonRoot = true
                seccompProfile = {
                  type = "RuntimeDefault"
                }
              }
              containers = local.containers
            },
            var.service_account_name != null ? { serviceAccountName = var.service_account_name } : {},
            length(local.all_pod_volumes) > 0 ? { volumes = local.all_pod_volumes } : {}
          )
        }
      },
      # For StatefulSet, add serviceName
      local.workload_type == "StatefulSet" ? { serviceName = var.metadata.name } : {}
    )
  }
}

resource "kubernetes_secret" "env" {
  for_each = nonsensitive(toset([for k, v in var.containers : k if v.variables != null]))

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

resource "kubernetes_manifest" "workload" {
  manifest = provider::deepmerge::mergo(
    local.base_manifest,
    local.ext_deployment_patch,
    local.ext_pod_patch
  )

  computed_fields = ["metadata.annotations", "metadata.labels"]

  wait {
    rollout = var.wait_for_rollout
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
