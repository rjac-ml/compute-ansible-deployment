include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/gke"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    network_name       = "pix-dev"
    subnetwork_name    = "pix-dev-private"
    pods_range_name    = "pix-dev-pods"
    services_range_name = "pix-dev-services"
  }
  mock_outputs_allowed_terraform_commands  = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  name               = include.root.locals.project_name
  environment        = include.root.locals.environment
  kubernetes_version = "1.35"
  zones              = ["us-central1-a", "us-central1-b"]

  network_name        = dependency.vpc.outputs.network_name
  subnetwork_name     = dependency.vpc.outputs.subnetwork_name
  pods_range_name     = dependency.vpc.outputs.pods_range_name
  services_range_name = dependency.vpc.outputs.services_range_name

  enable_private_nodes    = true
  enable_private_endpoint = false

  node_pools = [
    {
      name           = "pix-core"
      machine_type   = "e2-medium"
      min_count      = 1
      max_count      = 3
      initial_node_count = 1
      disk_size_gb   = 50
      disk_type      = "pd-standard"
      auto_repair    = true
      auto_upgrade   = true
      preemptible    = false
      spot           = false
    },
    {
      name           = "pix-compute"
      machine_type   = "c2-standard-4"
      min_count      = 0
      max_count      = 4
      initial_node_count = 0
      disk_size_gb   = 50
      disk_type      = "pd-ssd"
      auto_repair    = true
      auto_upgrade   = true
      preemptible    = false
      spot           = true
    }
  ]

  # CI/CD service account from shared/wif (set after WIF is deployed)
  cicd_service_account_email = ""

  labels = {
    service = "gke"
  }
}
