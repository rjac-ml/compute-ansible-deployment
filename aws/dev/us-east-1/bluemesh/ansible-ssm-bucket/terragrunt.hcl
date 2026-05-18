# Terragrunt config: S3 staging bucket for the Ansible SSM connection plugin.
#
# Path:   aws/dev/us-east-1/bluemesh/ansible-ssm-bucket
# Module: aws/terraform/modules/ansible-ssm-bucket
#
# One bucket per (account, region, versionmesh) — sits alongside ec2/ and vpc/
# inside the bluemesh tier. When greenmesh lands, it gets its own sibling
# bucket at aws/dev/us-east-1/greenmesh/ansible-ssm-bucket (copy this file).
#
# Applied by the existing aws-infra-provision.yaml workflow (which walks
# aws/<account>/<region>/<versionmesh>/ and runs `just aws-apply`). Idempotent:
# re-running against an already-converged state is `0 to add, 0 to change`.
#
# Spec: specs/003-ansible-node-exporter/research.md Finding 2.
# Phase: 2 (Foundational) — BLOCKING for the Ansible layer.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/ansible-ssm-bucket"
}

# Depend on the ec2 unit in this same versionmesh to wire the bucket policy
# to the right instance-profile role. (Same mesh → adjacent path → ../ec2.)
dependency "ec2" {
  config_path = "../ec2"

  mock_outputs = {
    iam_role_arn = "arn:aws:iam::000000000000:role/mock-instance-role"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  account_id            = include.root.locals.account_id
  region                = include.root.locals.aws_region
  versionmesh           = include.root.locals.versionmesh
  ec2_instance_role_arn = dependency.ec2.outputs.iam_role_arn

  tags = {
    Service = "ansible-ssm-bucket"
    Purpose = "ansible-ssm-staging"
  }
}
