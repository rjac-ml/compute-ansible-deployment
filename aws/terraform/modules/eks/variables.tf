variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "endpoint_public_access" {
  type = bool
}

variable "enable_cluster_creator_admin_permissions" {
  type = bool
}

variable "tags" {
  type = map(string)
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "private_subnets_cidr_blocks" {
  type = list(string)
}

variable "eks_managed_node_groups" {
  type    = any
  default = {}
}

variable "enable_eks_auto_mode" {
  type    = bool
  default = false
}

variable "enable_cluster_addons" {
  type    = map(bool)
  default = {}
}

variable "bootstrap_self_managed_addons" {
  type        = bool
  default     = true
  description = "Whether to bootstrap self-managed addons (vpc-cni, kube-proxy). Set false for Cilium CNI replacement."
}

variable "cicd_role_arn" {
  type        = string
  default     = ""
  description = "ARN of the IAM role for CI/CD (GitHub Actions OIDC) access to EKS"
}

variable "create_access_groups" {
  type        = bool
  default     = true
  description = "Create IAM groups for easier user access management (admin + developer)"
}

