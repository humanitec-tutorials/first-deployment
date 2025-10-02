output "hostname" {
  description = "PostgreSQL hostname"
  value       = "${random_id.release.hex}-rw.${var.namespace}.svc.cluster.local"
}

output "port" {
  description = "PostgreSQL port"
  value       = 5432
}

output "database" {
  description = "Database name"
  value       = "default"
}

output "username" {
  description = "Database username"
  value       = "db-user"
}

output "password" {
  description = "Database password"
  value       = random_password.pwd.result
  sensitive   = true
}