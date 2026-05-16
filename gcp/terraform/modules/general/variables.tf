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
  description = "Name prefix"
}

variable "environment" {
  type        = string
  description = "Environment (dev, prod, etc.)"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
}

variable "cluster_endpoint" {
  type        = string
  description = "GKE cluster endpoint"
  sensitive   = true
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Base64 encoded cluster CA certificate"
  sensitive   = true
}

variable "enable_secrets_store_csi" {
  type        = bool
  description = "Enable Secrets Store CSI Driver + GCP provider"
  default     = false
}

variable "secrets_store_csi_driver_version" {
  type        = string
  description = "Secrets Store CSI Driver Helm chart version"
  default     = "1.5.5"
}

variable "secrets_store_csi_provider_gcp_version" {
  type        = string
  description = "GCP Secrets Store CSI Provider image tag"
  default     = "1.11.0"
}
