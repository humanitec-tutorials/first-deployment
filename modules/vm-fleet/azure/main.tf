terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "random_id" "fleet_id" {
  byte_length = 8
}

# Get the current Azure subscription
data "azurerm_client_config" "current" {}

# Create a resource group for the fleet
resource "azurerm_resource_group" "fleet" {
  name     = "vm-fleet-${random_id.fleet_id.hex}"
  location = "East US"
}

# Create virtual network
resource "azurerm_virtual_network" "fleet" {
  name                = "fleet-vnet-${random_id.fleet_id.hex}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.fleet.location
  resource_group_name = azurerm_resource_group.fleet.name
}

# Create subnet
resource "azurerm_subnet" "fleet" {
  name                 = "fleet-subnet-${random_id.fleet_id.hex}"
  resource_group_name  = azurerm_resource_group.fleet.name
  virtual_network_name = azurerm_virtual_network.fleet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "fleet" {
  name                = "fleet-nsg-${random_id.fleet_id.hex}"
  location            = azurerm_resource_group.fleet.location
  resource_group_name = azurerm_resource_group.fleet.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate Network Security Group to the subnet
resource "azurerm_subnet_network_security_group_association" "fleet" {
  subnet_id                 = azurerm_subnet.fleet.id
  network_security_group_id = azurerm_network_security_group.fleet.id
}

# Create public IPs
resource "azurerm_public_ip" "fleet" {
  count               = 3
  name                = "fleet-public-ip-${random_id.fleet_id.hex}-${count.index + 1}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create Load Balancer
resource "azurerm_lb" "fleet" {
  name                = "fleet-lb-${random_id.fleet_id.hex}"
  location            = azurerm_resource_group.fleet.location
  resource_group_name = azurerm_resource_group.fleet.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "fleet-lb-frontend"
    public_ip_address_id = azurerm_public_ip.fleet_lb.id
  }
}

# Create public IP for load balancer
resource "azurerm_public_ip" "fleet_lb" {
  name                = "fleet-lb-public-ip-${random_id.fleet_id.hex}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create backend address pool
resource "azurerm_lb_backend_address_pool" "fleet" {
  loadbalancer_id = azurerm_lb.fleet.id
  name            = "fleet-backend-pool"
}

# Create health probe
resource "azurerm_lb_probe" "fleet" {
  loadbalancer_id = azurerm_lb.fleet.id
  name            = "fleet-http-probe"
  port            = 80
  protocol        = "Http"
  request_path    = "/"
}

# Create load balancing rule
resource "azurerm_lb_rule" "fleet" {
  loadbalancer_id                = azurerm_lb.fleet.id
  name                           = "fleet-lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fleet-lb-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.fleet.id]
  probe_id                       = azurerm_lb_probe.fleet.id
}

# Create Network Interfaces
resource "azurerm_network_interface" "fleet" {
  count               = 3
  name                = "fleet-nic-${random_id.fleet_id.hex}-${count.index + 1}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.fleet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.fleet[count.index].id
  }
}

# Associate Network Interface to the Backend Pool of the Load Balancer
resource "azurerm_network_interface_backend_address_pool_association" "fleet" {
  count                   = 3
  network_interface_id    = azurerm_network_interface.fleet[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.fleet.id
}

# Create virtual machines
resource "azurerm_linux_virtual_machine" "fleet" {
  count               = 3
  name                = "vm-${random_id.fleet_id.hex}-${count.index + 1}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  size                = "Standard_B2ls_v2"
  admin_username      = "ubuntu"

  # Disable password authentication in favor of SSH key authentication
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.fleet[count.index].id,
  ]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

output "loadbalancer_ip" {
  value = azurerm_public_ip.fleet_lb.ip_address
}

output "instance_ips" {
  value = azurerm_public_ip.fleet[*].ip_address
}

output "ssh_username" {
  value = "ubuntu"
}

output "ssh_private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}