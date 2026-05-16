variable "name" {
  type        = string
  description = "Base name for resources"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "cluster_endpoint" {
  type        = string
  description = "EKS cluster API endpoint"
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "EKS cluster CA certificate data (base64)"
}

variable "cilium_version" {
  type        = string
  description = "Cilium Helm chart version"
  default     = "1.17.3"
}

variable "enable_hubble" {
  type        = bool
  description = "Enable Hubble observability"
  default     = true
}

variable "enable_hubble_ui" {
  type        = bool
  description = "Enable Hubble UI"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
