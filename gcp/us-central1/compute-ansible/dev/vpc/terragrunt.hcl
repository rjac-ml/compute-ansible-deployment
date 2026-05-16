include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/vpc"
}

inputs = {
  name        = include.root.locals.project_name
  environment = include.root.locals.environment

  subnet_ip           = "10.1.0.0/20"
  pods_range_cidr     = "100.64.0.0/16"
  services_range_cidr = "100.65.0.0/20"
  enable_cloud_nat    = true
}
