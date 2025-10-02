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

resource "azurerm_storage_account" "storage" {
  name                     = "${substr(replace(var.storage_account_name, "-", ""), 0, 15)}${random_id.suffix.hex}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Allow blob public access for demo purposes (similar to GCS bucket)
  allow_nested_items_to_be_public = true
}

resource "azurerm_storage_container" "container" {
  name                  = "default"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "blob"
}