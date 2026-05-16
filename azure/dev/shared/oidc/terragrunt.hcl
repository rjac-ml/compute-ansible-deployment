include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/oidc"
}

inputs = {
  app_display_name = "next-signal-github-actions"
  subscription_id  = include.root.locals.subscription_id
  tags = {
    Service = "OIDC"
    Purpose = "GitHub-Actions"
  }
}
