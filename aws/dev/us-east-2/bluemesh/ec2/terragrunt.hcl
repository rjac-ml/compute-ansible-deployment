include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/ec2-extended"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id          = "vpc-mock"
    vpc_cidr_block  = "10.10.0.0/16"
    private_subnets = ["subnet-a", "subnet-b"]
  }
  mock_outputs_allowed_terraform_commands  = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  name        = "${include.root.locals.project_name}-${include.root.locals.account}-${include.root.locals.versionmesh}-${include.root.locals.region}"
  environment = include.root.locals.account

  vpc_id          = dependency.vpc.outputs.vpc_id
  vpc_cidr        = dependency.vpc.outputs.vpc_cidr_block
  private_subnets = dependency.vpc.outputs.private_subnets

  instances_per_az = 1
  instance_type    = "t2.micro"
  data_volume_size = 10

  dns_zone_name = "${include.root.locals.versionmesh}.compute-ansible.internal"

  deployment_code = "${include.root.locals.versionmesh}-${include.root.locals.account}-${include.root.locals.region}"

  deploy_id = run_cmd("--terragrunt-quiet", "git", "rev-parse", "--short", "HEAD")

  tags = {
    Service = "ec2-extended"
  }
}
