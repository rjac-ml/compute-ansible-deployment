output "vm_ids" {
  description = "IDs of all VMs"
  value       = [for v in azurerm_linux_virtual_machine.node : v.id]
}

output "vm_details" {
  description = "Map of VM name to details (id, private_ip, zone)"
  value = { for k, v in azurerm_linux_virtual_machine.node : k => {
    id         = v.id
    private_ip = v.private_ip_address
    zone       = v.zone
  } }
}

output "dns_zone_name" {
  description = "Private DNS zone name"
  value       = var.enable_dns ? var.dns_zone_name : ""
}

output "storage_account_name" {
  description = "Storage account name for mesh data"
  value       = var.enable_storage ? azurerm_storage_account.mesh[0].name : ""
}

output "deployment_code" {
  description = "Deployment code for service discovery"
  value       = var.deployment_code
}

output "ssh_private_key" {
  description = "SSH private key for VM access (sensitive)"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}
