variable "name" {
  type        = string
  description = "Name of the cluster"
}

variable "environment" {
  type        = string
  description = "Environment of the cluster"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the resources"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "cluster_endpoint" {
  type        = string
  description = "EKS cluster endpoint"
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "Base64 encoded certificate data for the cluster"
  sensitive   = true
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the EKS cluster is deployed"
}

variable "region" {
  type        = string
  description = "AWS region"
}

### Pod Identity Addons
variable "enable_aws_load_balancer_controller" {
  type        = bool
  description = "Enable AWS Load Balancer Controller Pod Identity and Helm deployment"
  default     = true
}

### LBC Helm Chart
variable "lbc_helm_chart_version" {
  type        = string
  description = "AWS Load Balancer Controller Helm chart version"
  default     = "1.14.0"
}

### Secrets Store CSI Driver (ASCP)
variable "enable_secrets_store_csi" {
  type        = bool
  description = "Enable Secrets Store CSI Driver and AWS provider (ASCP) for Pod Identity-based secret mounting"
  default     = false
}

variable "secrets_store_csi_provider_aws_version" {
  type        = string
  description = "AWS Secrets Store CSI Driver Provider Helm chart version"
  default     = "2.2.1"
}
