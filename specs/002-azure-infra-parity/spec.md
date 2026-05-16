# Feature Specification: Azure Infrastructure Parity

**Feature Branch**: `002-azure-infra-parity`
**Created**: 2026-05-12
**Status**: Draft
**Input**: User description: "Replicate AWS compute-ansible patterns in Azure: OIDC federation for GitHub Actions, Terragrunt root config, VMs across availability zones with tag-based discovery, GitHub Actions workflows. Start with azure/dev/eastus/bluemesh."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Azure Terragrunt Root Config & Directory Structure (Priority: P1)

As an infrastructure operator, I want the Azure directory to follow the same `<provider>/<account>/<region>/<versionmesh>` pattern as AWS, with a `root.hcl` that auto-derives subscription, region, and versionmesh from the path, so that deploying to Azure is operationally identical to deploying to AWS.

**Why this priority**: Everything else depends on the root config and directory convention being in place.

**Independent Test**: `terragrunt validate` from `azure/dev/eastus/bluemesh/vnet/` succeeds with correct azurerm provider configuration derived from the path.

**Acceptance Scenarios**:

1. **Given** the Azure directory is structured as `azure/dev/eastus/bluemesh/`, **When** root.hcl parses the path, **Then** `account = "dev"`, `region = "eastus"`, `versionmesh = "bluemesh"` are correctly derived.
2. **Given** `azure/dev/account.hcl` exists with subscription_id and tenant_id, **When** Terragrunt generates the provider, **Then** the azurerm provider is configured with the correct subscription and tenant.
3. **Given** the shared path `azure/dev/shared/oidc/`, **When** root.hcl parses it, **Then** `is_shared = true` and versionmesh is empty (same logic as AWS).

---

### User Story 2 - Azure VMs with Tag-Based Discovery (Priority: P2)

As an infrastructure operator, I want to deploy VMs across Azure availability zones in eastus with a `deployment_code` tag, so that VMs can discover their peers using Azure Resource Graph or CLI queries — the same pattern as AWS EC2 instances.

**Why this priority**: This is the core workload. The VMs should be plain compute instances (not Kubernetes), distributed across availability zones, with Route53-equivalent DNS (Azure Private DNS Zone) and S3-equivalent storage (Azure Storage Account).

**Independent Test**: After deploying, running `az vm list --query "[?tags.deployment_code=='bluemesh-dev-eastus']"` returns all VMs in the deployment with their private IPs.

**Acceptance Scenarios**:

1. **Given** `instances_per_az = 1` and eastus has 3 AZs, **When** I apply the VM module, **Then** 3 VMs are created, one per availability zone, each tagged with `deployment_code = "bluemesh-dev-eastus"`.
2. **Given** VMs are deployed with an Azure Private DNS Zone, **When** I query `node-1-1.bluemesh.compute-ansible.internal`, **Then** it resolves to the VM's private IP.
3. **Given** VMs have a managed identity with Reader role, **When** a VM runs `az vm list` filtered by `deployment_code`, **Then** all peer VMs are returned.

---

### User Story 3 - GitHub Actions OIDC & Workflows for Azure (Priority: P3)

As a CI/CD operator, I want GitHub Actions to authenticate with Azure using OIDC federation (workload identity), and I want plan/provision/destroy workflows that match the AWS pattern, so that Azure deployments follow the same git-driven process.

**Why this priority**: CI/CD automation completes the deployment loop. The OIDC federation (Azure AD App Registration + Federated Credential) is a prerequisite created outside Terraform (like AWS OIDC provider), with a step-by-step guide in `guide/azure/`.

**Independent Test**: Dispatching `azure-infra-plan.yaml` with `account=dev`, `region=eastus`, `cluster=bluemesh` runs `terragrunt plan --all` successfully using OIDC credentials.

**Acceptance Scenarios**:

1. **Given** Azure OIDC federation is set up per the guide, **When** GitHub Actions runs with `azure/login@v2`, **Then** it authenticates without any stored secrets (only client_id, tenant_id, subscription_id as non-secret variables).
2. **Given** the workflow dispatches with account/region/versionmesh inputs, **When** it runs, **Then** it calls `just azure-plan $ACCOUNT $REGION $CLUSTER` which targets the correct directory.
3. **Given** the `guide/azure/` directory, **When** a new operator reads `01-subscription-setup.md` through `03-oidc-federation.md`, **Then** they can set up Azure OIDC from scratch.

---

### User Story 4 - Setup Guides for Azure Prerequisites (Priority: P4)

As a new operator, I want step-by-step guides in `guide/azure/` that walk through creating the Azure subscription, resource groups, storage account for Terraform state, and OIDC federation for GitHub Actions, so that I can bootstrap the Azure environment from zero.

**Why this priority**: The guides document the one-time setup that must happen before Terragrunt can run. They are reference material, not IaC.

**Independent Test**: Following the guides from start to finish results in a working Azure environment where `just azure-plan dev eastus bluemesh` succeeds.

**Acceptance Scenarios**:

1. **Given** a user with only an Azure tenant, **When** they follow the guides in order, **Then** they have a subscription, resource group, storage account for state, and OIDC federation configured.
2. **Given** the OIDC guide, **When** a user runs the `az` CLI commands listed, **Then** a federated credential is created that GitHub Actions can use.

---

### Edge Cases

- What Azure VM sizes are available across all 3 AZs in eastus? Need to verify availability (learning from AWS us-east-1e issue).
- Azure state backend uses Azure Storage Account + blob container — how is locking handled? (Azure blob leases provide native locking.)
- Azure Private DNS Zones are global (not regional) — the DNS zone name must be unique per versionmesh.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Azure directory MUST follow `azure/<account>/<region>/<versionmesh>/<component>` pattern matching the AWS convention.
- **FR-002**: `azure/root.hcl` MUST auto-derive account, region, and versionmesh from the directory path, identical logic to `aws/root.hcl`.
- **FR-003**: Azure state backend MUST use Azure Storage Account with blob container, one per region per account. Naming: `sm<account><region>` (e.g., `smdeveastus`), container: `tfstate`.
- **FR-004**: All VMs MUST be tagged with `deployment_code` (`<versionmesh>-<account>-<region>`) for peer discovery.
- **FR-005**: VMs MUST have a managed identity with permissions to query Azure Resource Graph or `az vm list` for peer discovery.
- **FR-006**: GitHub Actions MUST authenticate via OIDC federation (Azure AD workload identity) — zero stored credentials.
- **FR-007**: Justfile MUST have `azure-plan`, `azure-apply`, `azure-destroy`, `azure-apply-shared` recipes matching the AWS pattern.
- **FR-008**: GitHub Actions workflows (`azure-infra-plan.yaml`, `azure-infra-provision.yaml`, `azure-infra-destroy.yaml`) MUST use the same dispatch input pattern (account, region, versionmesh).
- **FR-009**: Setup guides MUST be placed in `guide/azure/` as numbered markdown files covering subscription, state backend, and OIDC federation setup.
- **FR-010**: The OIDC federation (App Registration + Federated Credential) is treated as pre-existing in Terraform — referenced via data source, not created as a resource.

### Key Entities

- **Account**: Maps to an Azure subscription (dev, stage, prod). Contains subscription_id and tenant_id in `account.hcl`.
- **Versionmesh**: Same concept as AWS — independent deployment stack within account+region (bluemesh, redmesh, etc.).
- **Deployment Code**: Same tag format as AWS (`<versionmesh>-<account>-<region>`) for VM discovery.
- **Resource Group**: Azure grouping for all resources in a versionmesh deployment (`compute-ansible-<account>-<versionmesh>-<region>`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `terragrunt plan --all` succeeds from `azure/dev/eastus/bluemesh/` with correct provider and state configuration.
- **SC-002**: Any VM in the deployment can discover all peers by querying the `deployment_code` tag within 5 seconds.
- **SC-003**: GitHub Actions workflows authenticate via OIDC and run plan/apply/destroy without stored secrets.
- **SC-004**: A new operator can follow the `guide/azure/` docs and go from zero to working `terragrunt plan` in under 1 hour.
- **SC-005**: A new versionmesh (e.g., redmesh) can be created by copying a directory and adjusting inputs in under 10 minutes.

## Assumptions

- The user has an Azure tenant (Entra ID) but no subscription yet — guides will cover subscription creation.
- eastus region has 3 availability zones — VM sizes will be verified during planning.
- Azure Storage Account names are globally unique, 24 chars max, lowercase alphanumeric only. Convention: `sm<account><region>` (e.g., `smdeveastus`), container: `tfstate`.
- The `azurerm` Terraform provider requires subscription_id and tenant_id (no profile-based auth like AWS).
- GitHub OIDC federation uses Azure AD App Registration + Federated Credential — this is the Azure equivalent of AWS OIDC provider.
- The Terraform state storage account and container are created via CLI (guide), not Terraform (chicken-and-egg).
