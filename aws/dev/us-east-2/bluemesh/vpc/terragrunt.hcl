include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/vpc"
}

inputs = {
  name        = "${include.root.locals.project_name}-${include.root.locals.account}-${include.root.locals.versionmesh}-${include.root.locals.region}"
  environment = include.root.locals.account
  vpc_cidr                 = "10.20.0.0/16"
  secondary_cidr_blocks    = []
  availability_zones_count = 3
  azs                      = ["us-east-2a", "us-east-2b", "us-east-2c"]
  enable_database_subnets  = false
  single_nat_gateway       = true
}
