output "namespace_name" {
  description = "The name of the created Service Bus namespace"
  value       = azurerm_servicebus_namespace.namespace.name
}

output "namespace_id" {
  description = "The ID of the created Service Bus namespace"
  value       = azurerm_servicebus_namespace.namespace.id
}

output "topic_name" {
  description = "The name of the created Service Bus topic"
  value       = azurerm_servicebus_topic.topic.name
}

output "topic_id" {
  description = "The ID of the created Service Bus topic"
  value       = azurerm_servicebus_topic.topic.id
}