# Root configuration shared by all Azure Terragrunt units
# Path pattern: azure/<account>/<region>/<versionmesh>/<component>
# Shared pattern: azure/<account>/shared/<component>

locals {
  path_parts = split("/", path_relative_to_include())
  account    = local.path_parts[0]
  is_shared  = length(local.path_parts) >= 2 && local.path_parts[1] == "shared"

  region      = local.is_shared ? "" : local.path_parts[1]
  versionmesh = local.is_shared ? "" : local.path_parts[2]

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = local.is_shared ? null : read_terragrunt_config(find_in_parent_folders("region.hcl"))

  subscription_id = local.account_vars.locals.subscription_id
  tenant_id       = local.account_vars.locals.tenant_id
  azure_region    = local.is_shared ? "eastus" : local.region_vars.locals.region
  project_name    = "compute-ansible"
}

# Generate the Azure provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}
  subscription_id = "${local.subscription_id}"
  tenant_id       = "${local.tenant_id}"
  use_oidc        = true
  use_cli         = true
}
EOF
}

# Configure remote state (Azure Storage Account)
remote_state {
  backend = "azurerm"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    resource_group_name  = "compute-ansible-tfstate-${local.account}"
    storage_account_name = "smesh${local.account}${local.azure_region}"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    use_oidc             = true
    use_azuread_auth     = true
    subscription_id      = local.subscription_id
    tenant_id            = local.tenant_id
  }
}

# Common inputs passed to all modules
inputs = {
  region          = local.azure_region
  subscription_id = local.subscription_id
  tenant_id       = local.tenant_id
  account         = local.account
  versionmesh     = local.versionmesh
  tags = {
    Project     = "compute-ansible"
    Account     = local.account
    Region      = local.azure_region
    Versionmesh = local.versionmesh
    ManagedBy   = "terragrunt"
    Repo        = "next-signal/compute-ansible-machines"
  }
}
