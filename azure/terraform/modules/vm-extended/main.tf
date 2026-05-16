locals {
  name      = "${var.name}-${var.environment}"
  deploy_id = var.deploy_id != "" ? var.deploy_id : formatdate("YYYYMMDDhhmmss", timestamp())

  instances = { for pair in setproduct(range(length(var.subnet_ids)), range(var.instances_per_az)) :
    "node-${pair[0] + 1}-${pair[1] + 1}" => {
      subnet_id = var.subnet_ids[pair[0]]
      zone      = tostring(pair[0] + 1)
    }
  }

  storage_account_name = "smesh${replace(var.deployment_code, "-", "")}"
}

resource "azurerm_network_interface" "node" {
  for_each = local.instances

  name                = "${local.name}-${each.key}-nic"
  location            = var.region
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "node" {
  for_each = local.instances

  name                = "${local.name}-${each.key}"
  location            = var.region
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  zone                = each.value.zone
  admin_username      = var.admin_username

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  network_interface_ids = [azurerm_network_interface.node[each.key].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/user-data.sh", {
    deployment_code     = var.deployment_code
    resource_group_name = var.resource_group_name
  }))

  tags = merge(var.tags, {
    Name            = "${local.name}-${each.key}"
    DeployID        = local.deploy_id
    deployment_code = var.deployment_code
  })
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# --- Data Disks ---

resource "azurerm_managed_disk" "data" {
  for_each = local.instances

  name                 = "${local.name}-${each.key}-data"
  location             = var.region
  resource_group_name  = var.resource_group_name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  zone                 = each.value.zone
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = local.instances

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.node[each.key].id
  lun                = 0
  caching            = "None"
}

# --- Private DNS Zone ---
# VMs discover peers via auto-registered DNS records (no IAM role needed)

resource "azurerm_private_dns_zone" "mesh" {
  count               = var.enable_dns ? 1 : 0
  name                = var.dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "mesh" {
  count                 = var.enable_dns ? 1 : 0
  name                  = "${local.name}-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.mesh[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = true
  tags                  = var.tags
}

# --- Storage Account ---

resource "azurerm_storage_account" "mesh" {
  count                    = var.enable_storage ? 1 : 0
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.region
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "mesh" {
  count                 = var.enable_storage ? 1 : 0
  name                  = "data"
  storage_account_id    = azurerm_storage_account.mesh[0].id
  container_access_type = "private"
}
