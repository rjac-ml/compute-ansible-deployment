variable "github_org" {
  type        = string
  default     = "next-signal"
  description = "GitHub organization name"
}

variable "role_name" {
  type        = string
  default     = "github-actions-oidc-role"
  description = "Name of the IAM role for GitHub Actions"
}

variable "region" {
  type        = string
  description = "Region of the cluster"
}

variable "account_id" {
  type        = string
  description = "Account ID of the cluster"
}

variable "partition" {
  type        = string
  description = "Partition of the cluster"
  default     = "aws"
}

variable "github_repo_prefix" {
  type        = string
  description = "Prefix of the GitHub repository"
}

variable "github_trust_branches" {
  type        = list(string)
  description = "Branch patterns allowed to assume the OIDC role"
  default     = ["ref:refs/heads/main"]
}

variable "state_bucket_prefix" {
  type        = string
  description = "Prefix for Terragrunt state S3 buckets"
  default     = "compute-ansible-tg-state"
}

variable "state_environments" {
  type        = list(string)
  description = "List of environment names for Terragrunt state buckets"
  default     = ["shared", "dev", "prod"]
}

variable "data_bucket_prefix" {
  type        = string
  description = "Prefix for data S3 buckets (CI/CD needs s3:* on these)"
  default     = "compute-ansible"
}

variable "tags" {
  type    = map(string)
  default = {}
}
