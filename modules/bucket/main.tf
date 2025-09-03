terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 8
}

resource "google_storage_bucket" "bucket" {
  name          = "${var.google_storage_bucket_name}-${random_id.suffix.hex}"
  location      = "EU"
  force_destroy = true
}
