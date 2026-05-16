include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/oidc"
}

inputs = {
  github_org            = "next-signal"
  github_repo_prefix    = "compute-ansible"
  role_name             = "next-signal-github-actions"
  github_trust_branches = ["*"]
  state_bucket_prefix   = "compute-ansible-tg-state"
  region                = "us-east-1"
  account_id            = include.root.locals.account_id
  partition             = "aws"
  tags = {
    Service = "OIDC"
    Purpose = "GitHub-Actions"
  }
}
