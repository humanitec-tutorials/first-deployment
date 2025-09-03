output "name" {
  description = "The name of the Pub/Sub topic."
  value       = google_pubsub_topic.topic.name
}
