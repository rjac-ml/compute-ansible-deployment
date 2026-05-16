variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "github_org" {
  type        = string
  description = "GitHub organization name"
  default     = "pixemilar"
}

variable "github_repo_prefix" {
  type        = string
  description = "Prefix for GitHub repo trust"
}

variable "service_account_id" {
  type        = string
  description = "ID for the CI/CD service account"
  default     = "pixemilar-github-actions"
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to resources"
  default     = {}
}
