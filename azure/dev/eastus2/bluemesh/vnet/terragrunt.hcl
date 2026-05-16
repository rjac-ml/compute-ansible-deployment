include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/vnet"
}

inputs = {
  name         = "${include.root.locals.project_name}-${include.root.locals.account}-${include.root.locals.versionmesh}-${include.root.locals.azure_region}"
  environment  = include.root.locals.account
  region       = include.root.locals.azure_region
  address_space = "10.40.0.0/16"
  subnet_count = 3
}
