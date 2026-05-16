include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}//terraform/modules/vm-extended"
}

dependency "vnet" {
  config_path = "../vnet"
  mock_outputs = {
    resource_group_name = "mock-rg"
    vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    subnet_ids          = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet-1",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet-2",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet-3",
    ]
  }
  mock_outputs_allowed_terraform_commands  = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  name                = "${include.root.locals.project_name}-${include.root.locals.account}-${include.root.locals.versionmesh}-${include.root.locals.azure_region}"
  environment         = include.root.locals.account
  region              = include.root.locals.azure_region
  resource_group_name = dependency.vnet.outputs.resource_group_name
  vnet_id             = dependency.vnet.outputs.vnet_id
  subnet_ids          = [dependency.vnet.outputs.subnet_ids[0]]

  instances_per_az  = 2
  vm_size           = "Standard_B1s"
  data_disk_size_gb = 10

  dns_zone_name = "${include.root.locals.versionmesh}.compute-ansible.internal"

  deployment_code = "${include.root.locals.versionmesh}-${include.root.locals.account}-${include.root.locals.azure_region}"

  deploy_id = run_cmd("--terragrunt-quiet", "git", "rev-parse", "--short", "HEAD")

  tags = {
    Service = "vm-extended"
  }
}
