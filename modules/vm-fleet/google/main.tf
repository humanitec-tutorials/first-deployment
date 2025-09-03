terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "random_id" "fleet_id" {
  byte_length = 8
}

resource "google_compute_instance" "vm" {
  count        = 3
  name         = "vm-${random_id.fleet_id.hex}-${count.index + 1}"
  machine_type = "e2-micro"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh.public_key_openssh}"
  }

  tags = ["ssh", "http"]
}

resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh-${random_id.fleet_id.hex}"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh"]
}

resource "google_compute_firewall" "http" {
  name    = "allow-http-${random_id.fleet_id.hex}"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http"]
}
resource "google_compute_instance_group" "vms" {
  name = "vm-group-${random_id.fleet_id.hex}"
  
  instances = google_compute_instance.vm[*].self_link

  named_port {
    name = "http"
    port = "80"
  }

  depends_on = [google_compute_instance.vm]
}

resource "google_compute_backend_service" "default" {
  name        = "vm-backend-${random_id.fleet_id.hex}"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  backend {
    group = google_compute_instance_group.vms.id
  }

  health_checks = [google_compute_http_health_check.default.id]
}

resource "google_compute_http_health_check" "default" {
  name = "vm-health-check-${random_id.fleet_id.hex}"
  port = 80
}

resource "google_compute_url_map" "default" {
  name            = "vm-lb-${random_id.fleet_id.hex}"
  default_service = google_compute_backend_service.default.id
}

resource "google_compute_target_http_proxy" "default" {
  name    = "vm-proxy-${random_id.fleet_id.hex}"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "vm-forwarding-rule-${random_id.fleet_id.hex}"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
}

output "loadbalancer_ip" {
  value = google_compute_global_forwarding_rule.default.ip_address
}

output "instance_ips" {
  value = google_compute_instance.vm[*].network_interface[0].access_config[0].nat_ip
}

output "ssh_username" {
  value = "ubuntu"
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}
