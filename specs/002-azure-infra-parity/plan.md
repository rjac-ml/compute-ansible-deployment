# Implementation Plan: Azure Infrastructure Parity

**Branch**: `002-azure-infra-parity` | **Date**: 2026-05-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/002-azure-infra-parity/spec.md`

## Summary

Replicate the AWS compute-ansible deployment pattern in Azure: Terragrunt root config with azurerm provider/backend, VMs across availability zones with tag-based discovery, GitHub Actions OIDC workflows, and step-by-step setup guides. Start with `azure/dev/eastus/bluemesh`.

## Technical Context

**Language/Version**: HCL (Terraform 1.12.x, Terragrunt 0.81.x)
**Primary Dependencies**: `hashicorp/azurerm` provider ~> 4.x, `hashicorp/azuread` provider ~> 3.x
**Storage**: Azure Storage Account (`smdeveastus`) with blob container `tfstate`, azurerm backend
**Testing**: `terragrunt plan --all` (zero-diff validation), `just validate`
**Target Platform**: Azure (eastus, 3 AZs, subscription `compute-ansible-dev`)
**Project Type**: Infrastructure as Code (Terragrunt monorepo)
**Constraints**: Zero stored credentials (OIDC only), Terragrunt does NOT auto-create Azure storage accounts

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | PASS | All changes are HCL/Terragrunt |
| II. Git-Driven Deployment | PASS | GitHub Actions with OIDC |
| III. Directory-as-Contract | PASS | `azure/<account>/<region>/<versionmesh>` matches the pattern |
| IV. Spec-Driven Development | PASS | This is the SDD cycle |
| V. Automation via Just | PASS | New azure-* recipes |

## Project Structure

```text
azure/
├── root.hcl                                    # azurerm provider, azurerm backend
├── terraform/modules/
│   ├── vm-extended/                            # Azure VMs (mirrors ec2-extended)
│   ├── vnet/                                   # VNet + subnets + NSG + NAT
│   └── oidc/                                   # Data source for App Registration + role assignments
│
├── dev/
│   ├── account.hcl                             # subscription_id, tenant_id
│   ├── shared/
│   │   └── oidc/terragrunt.hcl
│   └── eastus/
│       ├── region.hcl
│       └── bluemesh/
│           ├── vnet/terragrunt.hcl
│           └── vm/terragrunt.hcl

guide/azure/
├── 01-subscription-setup.md
├── 02-state-backend-setup.md
├── 03-oidc-federation.md

.github/workflows/
├── azure-infra-plan.yaml
├── azure-infra-provision.yaml
├── azure-infra-destroy.yaml
```

## Phase 1 — Setup Guides (US4)

### 1.1 Subscription Setup (`guide/azure/01-subscription-setup.md`)

- Create or identify Azure subscription (`compute-ansible-dev`)
- Record `subscription_id` and `tenant_id`
- Create resource group `compute-ansible-tfstate-dev` for state storage

### 1.2 State Backend (`guide/azure/02-state-backend-setup.md`)

- Create storage account `smdeveastus` (Standard_LRS, TLS 1.2, no public blob access)
- Create blob container `tfstate`
- Grant `Storage Blob Data Contributor` to admin user and CI/CD service principal
- Locking: Azure blob leases (automatic, no extra config)

### 1.3 OIDC Federation (`guide/azure/03-oidc-federation.md`)

- Create App Registration `next-signal-github-actions`
- Create Service Principal
- Create Flexible Federated Credential via `az rest` (Graph API) with wildcard: `claims['sub'] matches 'repo:next-signal/compute-ansible-*:*'`
- Assign `Contributor` role at subscription scope
- Assign `Storage Blob Data Contributor` on state storage account
- Set GitHub Variables (not Secrets — these are non-sensitive IDs): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`

## Phase 2 — Root Config & Directory Structure (US1)

### 2.1 `azure/root.hcl`

Same path parsing as `aws/root.hcl`. Key differences:
- Provider: `azurerm` with `subscription_id`, `tenant_id`, `use_oidc = true`, `use_cli = true`
- Backend: `azurerm` with `use_oidc = true`, `use_azuread_auth = true`
- No provider-level default tags in azurerm — tags passed via `inputs`
- Loads `account.hcl` (subscription_id, tenant_id) and `region.hcl` (region)

### 2.2 Config Files

`azure/dev/account.hcl`:
```hcl
locals {
  account         = "dev"
  subscription_id = "PLACEHOLDER"
  tenant_id       = "PLACEHOLDER"
}
```

`azure/dev/eastus/region.hcl`:
```hcl
locals {
  region = "eastus"
}
```

## Phase 3 — Terraform Modules (US2)

### 3.1 `azure/terraform/modules/vnet/`

| Resource | Purpose |
|----------|---------|
| `azurerm_resource_group` | Resource group per versionmesh deployment |
| `azurerm_virtual_network` | VNet with address space |
| `azurerm_subnet` | One private subnet per AZ (3 in eastus) |
| `azurerm_network_security_group` | Allow intra-VNet traffic, outbound all |
| `azurerm_nat_gateway` + public IP | Outbound internet for private subnets |

### 3.2 `azure/terraform/modules/vm-extended/`

| Resource | Purpose |
|----------|---------|
| `azurerm_linux_virtual_machine` | One VM per AZ, `Standard_B2ats_v2`, `instances_per_az` variable |
| `azurerm_network_interface` | NIC per VM in corresponding subnet |
| `azurerm_managed_disk` + attachment | Data disk per VM |
| `azurerm_private_dns_zone` | DNS zone `<versionmesh>.compute-ansible.internal` |
| `azurerm_private_dns_zone_virtual_network_link` | Link VNet with auto-registration (VMs register automatically) |
| `azurerm_storage_account` + container | Shared blob storage per deployment |
| System-assigned managed identity | For peer discovery via Azure Resource Graph |
| `azurerm_role_assignment` | Reader role on resource group for managed identity |
| Cloud-init `user-data.sh` | Hostname via IMDS, peer discovery, write `/etc/compute-ansible/peers.json` |

Tags on all VMs: `deployment_code`, `Project`, `Account`, `Region`, `Versionmesh`, `ManagedBy`, `Repo`

### 3.3 `azure/terraform/modules/oidc/`

References pre-existing App Registration (data source, not resource):
- `data "azuread_application"` by display name
- `data "azuread_service_principal"`
- `azurerm_role_assignment` for Contributor at subscription scope
- Outputs: `client_id`, `principal_id`

## Phase 4 — GitHub Actions & Justfile (US3)

### 4.1 Justfile

New recipes matching AWS pattern:
```
azure-plan account region versionmesh
azure-apply account region versionmesh
azure-destroy account region versionmesh
azure-init account region versionmesh
azure-apply-shared account
azure-plan-shared account
```

### 4.2 Workflows

Auth via `ARM_*` env vars (no `azure/login` step needed for Terraform):
```yaml
env:
  ARM_USE_OIDC: "true"
  ARM_USE_AZUREAD: "true"
  ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

Three workflows: `azure-infra-plan.yaml`, `azure-infra-provision.yaml`, `azure-infra-destroy.yaml`

## Complexity Tracking

No constitution violations.
