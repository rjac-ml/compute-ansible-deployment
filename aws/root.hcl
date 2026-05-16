# Root configuration shared by all Terragrunt units
# Path pattern: aws/<account>/<region>/<versionmesh>/<component>
# Shared pattern: aws/<account>/shared/<component>

locals {
  path_parts = split("/", path_relative_to_include())
  account    = local.path_parts[0]
  is_shared  = length(local.path_parts) >= 2 && local.path_parts[1] == "shared"

  region      = local.is_shared ? "" : local.path_parts[1]
  versionmesh = local.is_shared ? "" : local.path_parts[2]

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = local.is_shared ? null : read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_id   = local.account_vars.locals.account_id
  aws_region   = local.is_shared ? "us-east-1" : local.region_vars.locals.region
  profile      = local.account_vars.locals.profile
  project_name = "compute-ansible"
}

# Generate the AWS provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
  profile = "${local.profile}"
  allowed_account_ids = ["${local.account_id}"]

  default_tags {
    tags = {
      Project     = "compute-ansible"
      Account     = "${local.account}"
      Region      = "${local.aws_region}"
      Versionmesh = "${local.versionmesh}"
      ManagedBy   = "terragrunt"
      Repo        = "next-signal/compute-ansible-machines"
    }
  }
}
EOF
}

# Configure remote state (S3 backend)
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "compute-ansible-tg-state-${local.account}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
    profile      = local.profile
  }
}

# Common inputs passed to all modules
inputs = {
  region      = local.aws_region
  account_id  = local.account_id
  account     = local.account
  versionmesh = local.versionmesh
  tags = {
    Project     = "compute-ansible"
    Account     = local.account
    Region      = local.aws_region
    Versionmesh = local.versionmesh
    ManagedBy   = "terragrunt"
    Repo        = "next-signal/compute-ansible-machines"
  }
}
