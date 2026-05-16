include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/wif"
}

inputs = {
  github_org         = "next-signal"
  github_repo_prefix = "compute-ansible"
  service_account_id = "next-signal-github-actions"

  labels = {
    service = "wif"
    purpose = "github-actions"
  }
}
