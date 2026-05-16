variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "zones" {
  type        = list(string)
  description = "GCP zones within the region"
}

variable "name" {
  type        = string
  description = "Name prefix for the cluster"
}

variable "environment" {
  type        = string
  description = "Environment (dev, prod, etc.)"
}

variable "kubernetes_version" {
  type        = string
  description = "GKE Kubernetes version"
}

variable "network_name" {
  type        = string
  description = "VPC network name (from VPC module)"
}

variable "subnetwork_name" {
  type        = string
  description = "Subnet name (from VPC module)"
}

variable "pods_range_name" {
  type        = string
  description = "Secondary range name for pods (from VPC module)"
}

variable "services_range_name" {
  type        = string
  description = "Secondary range name for services (from VPC module)"
}

variable "node_pools" {
  type        = any
  description = "List of node pool configurations"
  default     = []
}

variable "enable_private_nodes" {
  type        = bool
  description = "Enable private nodes (no external IPs)"
  default     = true
}

variable "enable_private_endpoint" {
  type        = bool
  description = "Enable private API endpoint only"
  default     = false
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR for the GKE master network"
  default     = "172.16.0.0/28"
}

variable "cicd_service_account_email" {
  type        = string
  description = "CI/CD service account email for cluster admin"
  default     = ""
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to resources"
  default     = {}
}
