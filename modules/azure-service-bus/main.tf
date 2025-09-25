terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 8
}

resource "azurerm_servicebus_namespace" "namespace" {
  name                = "${var.topic_name}-${random_id.suffix.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
}

resource "azurerm_servicebus_topic" "topic" {
  name         = "topic"
  namespace_id = azurerm_servicebus_namespace.namespace.id
}