terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 8
}

resource "google_pubsub_topic" "topic" {
  name = "${var.topic_name}-${random_id.suffix.hex}"
}
