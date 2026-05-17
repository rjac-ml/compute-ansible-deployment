# Terragrunt config: S3 staging bucket for the Ansible SSM connection plugin.
#
# Path: aws/dev/us-east-1/ansible-ssm-bucket
# Module: aws/terraform/modules/ansible-ssm-bucket
#
# This unit is intentionally outside the <versionmesh> dimension because the
# bucket is shared by every Ansible run targeting any versionmesh in this
# (account, region). Adding more versionmeshes does NOT require more buckets.
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

# The bucket grants its access policy to the ec2-extended instance-profile
# role so the SSM agent on each target host can stage/retrieve file payloads
# during a playbook run.
#
# We deliberately depend on bluemesh/ec2 (the only versionmesh today). When
# greenmesh lands, this stanza needs to fan out across both meshes — see
# the migration note at the bottom of this file.
dependency "ec2_bluemesh" {
  config_path = "../bluemesh/ec2"

  mock_outputs = {
    iam_role_arn = "arn:aws:iam::000000000000:role/mock-instance-role"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  account_id            = include.root.locals.account_id
  region                = include.root.locals.aws_region
  ec2_instance_role_arn = dependency.ec2_bluemesh.outputs.iam_role_arn

  tags = {
    Service = "ansible-ssm-bucket"
    Purpose = "ansible-ssm-staging"
  }
}

# --- Migration note (greenmesh) ---
# When greenmesh is introduced, the bucket policy needs to grant BOTH
# versionmesh instance roles. Options at that time:
#   (a) Make ec2_instance_role_arn a list and update the bucket policy
#       module to iterate; depend on both ../bluemesh/ec2 and ../greenmesh/ec2.
#   (b) Move the per-mesh grant into a separate aws_iam_role_policy attached
#       to each ec2-extended instance role (no bucket-policy fanout needed).
# Both are mechanical changes; not in v1 scope.
