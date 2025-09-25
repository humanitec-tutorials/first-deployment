variable "storage_account_name" {
  description = "The name of the Azure Storage Account (will be made globally unique with suffix)."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "The Azure location/region."
  type        = string
}