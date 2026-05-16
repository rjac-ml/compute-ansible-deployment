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
  vpc_cidr                 = "10.10.0.0/16"
  secondary_cidr_blocks    = []
  availability_zones_count = 6
  azs                      = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"]
  enable_database_subnets  = false
  single_nat_gateway       = true
}
