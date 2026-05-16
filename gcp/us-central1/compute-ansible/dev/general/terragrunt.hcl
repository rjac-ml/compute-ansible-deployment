include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/general"
}

dependency "gke" {
  config_path = "../gke"
  mock_outputs = {
    cluster_name           = "pix-dev"
    cluster_endpoint       = "10.0.0.1"
    cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
  }
  mock_outputs_allowed_terraform_commands  = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  name        = include.root.locals.project_name
  environment = include.root.locals.environment

  cluster_name           = dependency.gke.outputs.cluster_name
  cluster_endpoint       = dependency.gke.outputs.cluster_endpoint
  cluster_ca_certificate = dependency.gke.outputs.cluster_ca_certificate

  enable_secrets_store_csi = true
}
