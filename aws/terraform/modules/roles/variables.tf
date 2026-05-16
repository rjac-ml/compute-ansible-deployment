variable "name" {
  type        = string
  description = "Name prefix for resources"
}

variable "environment" {
  type        = string
  description = "Environment (dev, prod, etc.)"
}

variable "create_access_groups" {
  type        = bool
  default     = true
  description = "Create IAM groups for easier user access management"
}

variable "cicd_trusted_principal_arns" {
  type        = list(string)
  default     = []
  description = "List of IAM role/user ARNs that can assume the CI/CD role. If empty, any principal in the account can assume (not recommended for prod)."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "github_org" {
  type        = string
  default     = "pixemilar"
  description = "GitHub organization for OIDC trust policy"
}
