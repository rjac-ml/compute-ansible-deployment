variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "name" {
  type        = string
  description = "Name prefix for resources"
}

variable "environment" {
  type        = string
  description = "Environment (dev, prod, etc.)"
}

variable "subnet_ip" {
  type        = string
  description = "Primary CIDR for the private subnet"
}

variable "pods_range_cidr" {
  type        = string
  description = "Secondary IP range CIDR for GKE pods"
}

variable "services_range_cidr" {
  type        = string
  description = "Secondary IP range CIDR for GKE services"
}

variable "enable_cloud_nat" {
  type        = bool
  description = "Enable Cloud NAT for private subnet"
  default     = true
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to resources"
  default     = {}
}
