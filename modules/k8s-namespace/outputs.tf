output "namespace" {
  description = "The name of the Kubernetes namespace."
  value       = kubernetes_namespace.namespace.metadata[0].name
}