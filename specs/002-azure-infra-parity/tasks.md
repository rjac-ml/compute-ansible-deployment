# Tasks: Azure Infrastructure Parity

**Input**: Design documents from `specs/002-azure-infra-parity/`
**Prerequisites**: plan.md (required), spec.md (required), research.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)

## Path Conventions

- Terraform modules: `azure/terraform/modules/<name>/`
- Terragrunt configs: `azure/<account>/<region>/<versionmesh>/<component>/terragrunt.hcl`
- Setup guides: `guide/azure/`

---

## Phase 1: Setup Guides (US4)

**Purpose**: Document the one-time prerequisites before any Terraform can run

- [ ] T001 [P] [US4] Create `guide/azure/01-subscription-setup.md` — step-by-step: create subscription `compute-ansible-dev` (or identify existing), record `subscription_id` and `tenant_id`, create resource group `compute-ansible-tfstate-dev` in eastus, install Azure CLI (`az`)
- [ ] T002 [P] [US4] Create `guide/azure/02-state-backend-setup.md` — step-by-step: create storage account `smdeveastus` (Standard_LRS, TLS 1.2, `--allow-blob-public-access false`), create blob container `tfstate`, grant `Storage Blob Data Contributor` to admin user, verify with `az storage account check-name`
- [ ] T003 [US4] Create `guide/azure/03-oidc-federation.md` — step-by-step: create App Registration `next-signal-github-actions`, create Service Principal, create Flexible Federated Credential via `az rest` with `claimsMatchingExpression` matching `repo:next-signal/compute-ansible-*:*`, assign `Contributor` + `Storage Blob Data Contributor` roles, set GitHub Variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`)

**Checkpoint**: Guides ready. User can follow them to bootstrap Azure before Terraform runs.

---

## Phase 2: Foundational (Root Config + Directory Structure) (US1)

**Purpose**: Create the Terragrunt root config and directory convention for Azure

- [ ] T004 Create `azure/dev/account.hcl` with locals: `account = "dev"`, `subscription_id = "PLACEHOLDER"`, `tenant_id = "PLACEHOLDER"`
- [ ] T005 Create `azure/dev/eastus/region.hcl` with locals: `region = "eastus"`
- [ ] T006 Create `azure/root.hcl` — parse path (same logic as `aws/root.hcl`), generate azurerm provider with `subscription_id`, `tenant_id`, `use_oidc = true`, `use_cli = true`, configure azurerm backend with `use_oidc = true`, `use_azuread_auth = true`, storage account `sm${local.account}${local.azure_region}`, container `tfstate`, handle shared path case, pass common inputs (tags, region, account, versionmesh)

**Checkpoint**: Root config in place. Terragrunt can parse `azure/dev/eastus/bluemesh/` paths.

---

## Phase 3: User Story 2 - Azure Terraform Modules (Priority: P2)

**Goal**: Create vnet and vm-extended modules for Azure, matching the AWS ec2-extended pattern.

**Independent Test**: `terraform validate` passes for both modules.

### VNet Module

- [ ] T007 [P] [US2] Create `azure/terraform/modules/vnet/main.tf` — `azurerm_resource_group`, `azurerm_virtual_network` with address space, `azurerm_subnet` (one per AZ, 3 for eastus), `azurerm_network_security_group` (allow intra-VNet + outbound), `azurerm_nat_gateway` + `azurerm_public_ip` for outbound, associate NSG and NAT to subnets
- [ ] T008 [P] [US2] Create `azure/terraform/modules/vnet/variables.tf` — `name`, `environment`, `region`, `address_space` (default `10.30.0.0/16`), `subnet_count`, `tags`
- [ ] T009 [P] [US2] Create `azure/terraform/modules/vnet/outputs.tf` — `resource_group_name`, `vnet_name`, `vnet_id`, `subnet_ids`, `nsg_id`
- [ ] T010 [P] [US2] Create `azure/terraform/modules/vnet/versions.tf` — require `hashicorp/azurerm` ~> 4.0

### VM Extended Module

- [ ] T011 [P] [US2] Create `azure/terraform/modules/vm-extended/variables.tf` — `name`, `environment`, `region`, `resource_group_name`, `vnet_id`, `subnet_ids`, `instances_per_az`, `vm_size` (default `Standard_B2ats_v2`), `data_disk_size_gb`, `deployment_code`, `enable_dns`, `dns_zone_name`, `enable_storage`, `deploy_id`, `tags`
- [ ] T012 [P] [US2] Create `azure/terraform/modules/vm-extended/versions.tf` — require `hashicorp/azurerm` ~> 4.0
- [ ] T013 [US2] Create `azure/terraform/modules/vm-extended/main.tf` — locals for instance map (AZ × instances_per_az), `azurerm_network_interface` per VM, `azurerm_linux_virtual_machine` per VM with system-assigned managed identity and `deployment_code` tag, `azurerm_managed_disk` + attachment for data disks, `azurerm_private_dns_zone` + VNet link with auto-registration, `azurerm_storage_account` + container for shared data, `azurerm_role_assignment` (Reader on resource group for managed identity), cloud-init via `custom_data`
- [ ] T014 [US2] Create `azure/terraform/modules/vm-extended/user-data.sh` — cloud-init script: install `jq` + `az` CLI, mount data disk, set hostname via IMDS (`curl -H "Metadata:true" http://169.254.169.254/metadata/instance`), discover peers via `az vm list --resource-group <rg> --query "[?tags.deployment_code=='<code>']"`, write `/etc/compute-ansible/peers.json`, retry loop (10 retries, 5s backoff)
- [ ] T015 [P] [US2] Create `azure/terraform/modules/vm-extended/outputs.tf` — `vm_ids`, `vm_details` (name, ip, az), `dns_zone_name`, `dns_records`, `storage_account_name`, `deployment_code`
- [ ] T016 [US2] Validate both modules: `terraform init -backend=false && terraform validate` for vnet and vm-extended

**Checkpoint**: Modules validate. Ready for terragrunt wiring.

---

## Phase 4: User Story 1 - Terragrunt Configs (Priority: P1)

**Goal**: Wire the modules into the directory structure with terragrunt.hcl files.

- [ ] T017 [P] [US1] Create `azure/dev/eastus/bluemesh/vnet/terragrunt.hcl` — include root.hcl, source vnet module, inputs: name, environment, region, address_space `10.30.0.0/16`, subnet_count 3
- [ ] T018 [P] [US1] Create `azure/dev/eastus/bluemesh/vm/terragrunt.hcl` — include root.hcl, source vm-extended module, dependency on vnet, inputs: instances_per_az 1, vm_size `Standard_B2ats_v2`, data_disk_size_gb 10, dns_zone_name `bluemesh.compute-ansible.internal`, deployment_code from root locals
- [ ] T019 [US1] Create `azure/dev/shared/oidc/terragrunt.hcl` — include root.hcl, source oidc module, inputs: app_display_name `next-signal-github-actions`

### OIDC Module

- [ ] T020 [P] [US1] Create `azure/terraform/modules/oidc/main.tf` — `data "azuread_application"` by display name, `data "azuread_service_principal"`, `azurerm_role_assignment` (Contributor at subscription scope)
- [ ] T021 [P] [US1] Create `azure/terraform/modules/oidc/variables.tf` — `app_display_name`, `subscription_id`, `tags`
- [ ] T022 [P] [US1] Create `azure/terraform/modules/oidc/outputs.tf` — `client_id`, `principal_id`, `app_display_name`
- [ ] T023 [P] [US1] Create `azure/terraform/modules/oidc/versions.tf` — require `hashicorp/azurerm` ~> 4.0, `hashicorp/azuread` ~> 3.0

**Checkpoint**: Terragrunt configs wired. `terragrunt validate` from new paths should work.

---

## Phase 5: User Story 3 - GitHub Actions & Justfile (Priority: P3)

- [ ] T024 [P] [US3] Update `justfile` — add `azure-plan`, `azure-apply`, `azure-destroy`, `azure-init`, `azure-apply-shared`, `azure-plan-shared` recipes with `account region versionmesh` pattern, path `azure/{{account}}/{{region}}/{{versionmesh}}`
- [ ] T025 [P] [US3] Create `.github/workflows/azure-infra-plan.yaml` — workflow_dispatch with account/region/versionmesh inputs, `ARM_USE_OIDC=true`, `ARM_USE_AZUREAD=true`, `ARM_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` from `vars.*`, install Terraform + Terragrunt + Just, run `just azure-init` + `just azure-plan`
- [ ] T026 [P] [US3] Create `.github/workflows/azure-infra-provision.yaml` — same as plan but runs `just azure-apply`
- [ ] T027 [P] [US3] Create `.github/workflows/azure-infra-destroy.yaml` — same as plan but runs `just azure-destroy`

**Checkpoint**: CI/CD ready. Workflows can be dispatched from GitHub Actions.

---

## Phase 6: Polish & Validation

- [ ] T028 [P] Update `CLAUDE.md` — add Azure section to module layout, commands, and architecture
- [ ] T029 Run `just fmt` and `just validate` for all Azure modules
- [ ] T030 Verify `terragrunt render-json` from `azure/dev/eastus/bluemesh/vnet/` shows correct provider config

---

## Dependencies & Execution Order

- **Phase 1 (Guides)**: No deps — can start immediately, parallel with Phase 2
- **Phase 2 (Root Config)**: No deps on Phase 1 (config files don't depend on Azure resources existing)
- **Phase 3 (Modules)**: No deps on Phase 2 (modules validate independently)
- **Phase 4 (Terragrunt Configs)**: Depends on Phase 2 (root.hcl) + Phase 3 (modules)
- **Phase 5 (CI/CD)**: Depends on Phase 4 (directory paths must exist)
- **Phase 6 (Polish)**: Depends on all above

### Parallel Opportunities

- T001 + T002 + T003 (guides)
- T007 + T008 + T009 + T010 (vnet module files)
- T011 + T012 + T015 (vm-extended vars/versions/outputs)
- T017 + T018 (terragrunt configs)
- T020 + T021 + T022 + T023 (oidc module files)
- T024 + T025 + T026 + T027 (justfile + workflows)

---

## Implementation Strategy

### Batch 1: Guides + Root Config + Modules (T001-T016)
All can proceed in parallel since guides are docs, root config is independent, and modules validate standalone.

### Batch 2: Terragrunt Configs + OIDC Module (T017-T023)
Wire everything together.

### Batch 3: CI/CD + Polish (T024-T030)
GitHub Actions and docs.

---

## Notes

- Azure has no provider-level `default_tags` — tags must be passed to each resource via `tags` variable
- Terragrunt does NOT auto-create Azure storage accounts — bootstrap via guide
- `ARM_USE_OIDC=true` env var covers both provider and backend auth
- No `azure/login` GitHub Action step needed for Terraform-only workflows
- Azure Private DNS Zones are global resources, not regional — zone name must be unique per versionmesh
