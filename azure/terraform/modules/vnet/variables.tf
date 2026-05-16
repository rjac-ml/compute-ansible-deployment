variable "name" {
  type        = string
  description = "Base name for all resources"
}

variable "environment" {
  type        = string
  description = "Account/environment name (dev, stage, prod)"
}

variable "region" {
  type        = string
  description = "Azure region"
}

variable "address_space" {
  type        = string
  description = "VNet address space CIDR"
  default     = "10.30.0.0/16"
}

variable "subnet_count" {
  type        = number
  description = "Number of subnets (typically matches AZ count)"
  default     = 3
}

variable "tags" {
  type        = map(string)
  description = "Tags for all resources"
  default     = {}
}
