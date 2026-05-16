variable "app_display_name" {
  type        = string
  description = "Display name of the pre-existing App Registration for GitHub Actions OIDC"
  default     = "next-signal-github-actions"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID for role assignments"
}

variable "tags" {
  type        = map(string)
  description = "Tags for resources"
  default     = {}
}
