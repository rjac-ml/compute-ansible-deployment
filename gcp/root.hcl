# Root configuration shared by all GCP Terragrunt units

locals {
  # Parse the path to extract region, project, and environment
  path_parts  = split("/", path_relative_to_include())
  region      = local.path_parts[0]
  environment = local.path_parts[2]

  # Load region config
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id   = local.region_vars.locals.project_id
  gcp_region   = local.region_vars.locals.region
  project_name = "compute-ansible"
}

# Generate the Google provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "google" {
  project = "${local.project_id}"
  region  = "${local.gcp_region}"

  default_labels = {
    project     = "compute-ansible-${local.environment}"
    environment = "${local.environment}"
    managed_by  = "terragrunt"
    repo        = "next-signal-compute-ansible-machines"
  }
}

provider "google-beta" {
  project = "${local.project_id}"
  region  = "${local.gcp_region}"

  default_labels = {
    project     = "compute-ansible-${local.environment}"
    environment = "${local.environment}"
    managed_by  = "terragrunt"
    repo        = "next-signal-compute-ansible-machines"
  }
}
EOF
}

# Configure remote state (GCS backend)
remote_state {
  backend = "gcs"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket   = "compute-ansible-tg-state-gcp-${local.environment}"
    prefix   = "${path_relative_to_include()}/terraform.tfstate"
    project  = local.project_id
    location = local.gcp_region
  }
}

# Common inputs passed to all modules
inputs = {
  project_id  = local.project_id
  region      = local.gcp_region
  environment = local.environment
  labels = {
    project     = "compute-ansible-${local.environment}"
    environment = local.environment
    managed_by  = "terragrunt"
    repo        = "next-signal-compute-ansible-machines"
  }
}
