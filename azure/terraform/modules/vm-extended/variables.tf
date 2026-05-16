variable "name" {
  type        = string
  description = "Base name for all resources"
}

variable "environment" {
  type        = string
  description = "Account/environment name"
}

variable "region" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to deploy into"
}

variable "vnet_id" {
  type        = string
  description = "VNet ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs (VMs distributed across these)"
}

variable "instances_per_az" {
  type        = number
  description = "Number of VMs per availability zone (1 VM per subnet)"
  default     = 1
}

variable "vm_size" {
  type = string
  # Standard_B1s ($0.0104/hr) — BS Family, has default quota on new subscriptions
  # Upgrade to Standard_B2ats_v2 ($0.009/hr) when Basv2 quota is available
  description = "Azure VM size"
  default     = "Standard_B1s"
}

variable "data_disk_size_gb" {
  type        = number
  description = "Size of the data managed disk in GB"
  default     = 10
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VMs"
  default     = "compute-ansible"
}

variable "deployment_code" {
  type        = string
  description = "Unique deployment identifier for tag-based discovery (format: versionmesh-account-region)"
  default     = ""
}

variable "enable_dns" {
  type        = bool
  description = "Create Azure Private DNS Zone with auto-registration"
  default     = true
}

variable "dns_zone_name" {
  type        = string
  description = "Private DNS zone domain name"
  default     = "compute-ansible.internal"
}

variable "enable_storage" {
  type        = bool
  description = "Create Azure Storage Account for shared data"
  default     = true
}

variable "deploy_id" {
  type        = string
  description = "Unique identifier for this deployment run"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags for all resources"
  default     = {}
}
