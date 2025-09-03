terraform {
  required_providers {
    ansibleplay = {
      source  = "humanitec/ansibleplay"
    }  
  }
}

variable "ips" {
  type = list(string)
}

variable "loadbalancer" {
  type = string
}

variable "ssh_user" {
  type = string
}

variable "ssh_private_key" {
  type = string
}

variable "metadata" {
  type        = any
  description = "The metadata section of the Score file."
}

variable "containers" {
  type = map(object({
    image = string
    command = optional(list(string))
    args = optional(list(string))
    variables = optional(map(string))
    files = optional(map(object({
      source = optional(string)
      content = optional(string)
      binaryContent = optional(string)
      mode = optional(string)
    })))
    volumes = optional(map(object({
      source = string
      path = optional(string)
      readOnly = optional(bool)
    })))
    resources = optional(object({
      limits = optional(object({
        memory = optional(string)
        cpu = optional(string)
      }))
      requests = optional(object({
        memory = optional(string)
        cpu = optional(string)
      }))
    }))
  }))
  description = "The containers section of the Score file."
}

variable "service" {
  type = object({
    ports = optional(map(object({
      port = number
      protocol = optional(string)
      targetPort = optional(number)
    })))
  })
  description = "The service section of the Score file."
  default     = null
}

resource "terraform_data" "install_ansible" {
  provisioner "local-exec" {
    command = "apk add --no-cache ansible openssh-client && sleep 2"
  }
  triggers_replace = {
    always_run = timestamp()
  }
}

resource "local_file" "ssh_key" {
  filename        = "/tmp/ssh_key"
  content         = var.ssh_private_key
  file_permission = "0600"
}

locals {
  first_service_name = try(element(sort(keys(var.containers)), 0), "")
}

resource "local_file" "container_files" {
  for_each = merge([for k, v in var.containers : { for p, f in coalesce(v.files, {}) : sha256(join(",", [k, p])) => f.content if f.content != null }]...)
  filename        = "/tmp/${each.key}"
  content         = each.value
  file_permission = "0600"
}

resource "local_file" "binary_container_files" {
  for_each = merge([for k, v in var.containers : { for p, f in coalesce(v.files, {}) : sha256(join(",", [k, p])) => f.binaryContent if f.binaryContent != null }]...)
  filename        = "/tmp/${each.key}"
  content_base64  = each.value
  file_permission = "0600"
}

resource "ansibleplay_run" "setup" {
  hosts = var.ips
  playbook_file   = "${path.module}/playbook.yml"  # Path to your playbook file
  extra_vars_json = jsonencode({
    ansible_user                = var.ssh_user
    ansible_ssh_private_key_file = local_file.ssh_key.filename
    ansible_ssh_common_args     = "-o StrictHostKeyChecking=no"

    project_name = var.metadata.name
    compose_content = jsonencode({
      services = {for k, v in var.containers : k => merge({
          image = v.image
          entrypoint = v.command
          command = v.args
          environment = coalesce(v.variables, {})
          volumes = [ for p, f in coalesce(v.files, {}) : ( f.source != null ? {
            type = "bind"
            source = f.source
            target = p
            read_only = coalesce(f.readOnly, false)
          } : {
            type = "bind"
            source = "/home/${var.ssh_user}/compose/${var.metadata.name}/files/${sha256(join(",", k, p))}"
            target = p
            read_only = coalesce(f.readOnly, false)
          })]
          ports = k == local.first_service_name ? [for n, v in try(var.service.ports, {}) : {
            name = n
            published = tostring(v.port)
            target = coalesce(v.targetPort, v.port)
            protocol = lower(coalesce(v.protocol, "tcp"))
          }] : []
        },
        k == local.first_service_name ? {} : {
          network_mode = "service:${local.first_service_name}"
        },
        try(v.resources.requests.memory, "") == "" ? {} : {
          mem_limit = lower(v.resources.requests.memory)
        },
        try(v.resources.limits.memory, "") == "" ? {} : {
          mem_limit = lower(v.resources.limits.memory)
        },
        try(v.resources.requests.cpu, 0) == 0 ? {} : {
          cpus = v.resources.requests.cpu
        },
        try(v.resources.limits.cpu, 0) == 0 ? {} : {
          cpus = v.resources.limits.cpu
        })
      }
    })
    compose_files = flatten([for k, v in var.containers : [for p, f in coalesce(v.files, {}) : sha256(join(",", k, p))]]...)
  })
  depends_on = [local_file.container_files, local_file.binary_container_files, local_file.ssh_key, terraform_data.install_ansible]
}

output "loadbalancer" {
  value = var.loadbalancer
}
