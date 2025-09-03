output "name" {
  description = "The name of the Google Cloud Storage bucket."
  value       = google_storage_bucket.bucket.name
}
