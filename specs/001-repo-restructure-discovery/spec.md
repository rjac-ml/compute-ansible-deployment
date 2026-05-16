# Feature Specification: Repository Restructure & VM Service Discovery

**Feature Branch**: `001-repo-restructure-discovery`
**Created**: 2026-05-11
**Status**: Draft
**Input**: User description: "Restructure repo layout from provider/region/app/env/color to provider/account/region/versionmesh pattern; add EC2 service discovery via tags and registry so VMs can identify each other; start with AWS then extend to GCP"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Restructure Repository Layout to Account-First Pattern (Priority: P1)

As an infrastructure operator, I want the repository to follow a `<provider>/<account>/<region>/<versionmesh>` directory pattern so that the path clearly encodes which cloud account (dev, stage, prod, cust1) a deployment targets, and the deployment version is identified by a `<version>mesh` naming convention (e.g., bluemesh, redmesh, greenmesh).

**Why this priority**: This is the foundational change — every other feature depends on the new directory structure. The current pattern (`aws/us-east-1/compute-ansible/dev/kubeadm`) buries the account level deep in the path and uses application-specific names. The new pattern (`aws/dev/us-east-1/bluemesh`) puts the account (which maps to an AWS account boundary) at the top level, making it immediately clear which account is being targeted.

**Independent Test**: After restructuring, `terragrunt plan --all` from within any `<provider>/<account>/<region>/<versionmesh>/` path must succeed with no errors. The `root.hcl` must correctly derive account, region, and deployment version from the new path structure.

**Acceptance Scenarios**:

1. **Given** the repository has been restructured to the new layout, **When** I navigate to `aws/dev/us-east-1/bluemesh/` and run `terragrunt plan --all`, **Then** Terragrunt resolves the correct AWS account, region, state backend, and provider configuration automatically from the path.
2. **Given** the new directory convention, **When** I create a new deployment `aws/dev/us-east-1/redmesh/`, **Then** it operates independently from `bluemesh` with its own state, and the naming follows the `<version>mesh` pattern.
3. **Given** the `root.hcl` is updated for the new path structure, **When** I look at the parsed `path_parts`, **Then** `path_parts[0]` is the account (dev/stage/prod), `path_parts[1]` is the region, and `path_parts[2]` is the versionmesh identifier.

---

### User Story 2 - EC2 Service Discovery via Tags and Registry (Priority: P2)

As an infrastructure operator deploying a cluster of EC2 instances (like the existing kubeadm lab), I want each VM to be able to discover all other VMs in the same deployment using a `deployment_code` tag and AWS resource tagging APIs, so that instances can programmatically find their peers without hardcoding IPs or relying solely on DNS records.

**Why this priority**: The kubeadm module already deploys VMs with Route 53 DNS, but the DNS approach requires knowing instance names upfront. A tag-based discovery mechanism (using a shared `deployment_code` tag) allows dynamic peer discovery — any instance can query the EC2 API to find all instances sharing the same `deployment_code`, regardless of how many exist or what they're named.

**Independent Test**: After deploying VMs, an instance can use `aws ec2 describe-instances` filtered by the `deployment_code` tag to find all peer instances and retrieve their private IPs.

**Acceptance Scenarios**:

1. **Given** a deployment with a `deployment_code` tag (e.g., `bluemesh-dev-us-east-1`), **When** I run `aws ec2 describe-instances --filters "Name=tag:deployment_code,Values=bluemesh-dev-us-east-1"` from any instance in the deployment, **Then** all instances in that deployment are returned with their private IPs and roles.
2. **Given** two independent deployments (`bluemesh` and `redmesh`) in the same account, **When** instances in `bluemesh` query the `deployment_code` tag, **Then** only `bluemesh` instances are returned — no cross-deployment leakage.
3. **Given** the `deployment_code` tag is applied via Terraform, **When** I run `terragrunt plan`, **Then** all EC2 instances and spot instance requests include the `deployment_code` tag with the correct value derived from the versionmesh name.

---

### User Story 3 - Update GitHub Actions & Justfile for New Layout (Priority: P3)

As a CI/CD operator, I want the GitHub Actions workflows and justfile to work with the new `<provider>/<account>/<region>/<versionmesh>` directory layout so that automated deployments continue to function after the restructure.

**Why this priority**: The CI/CD pipeline and justfile are the operational interface — they must match the new directory structure. This is lower priority because the restructure (US1) and discovery (US2) can be validated locally first, but CI/CD must work before merging to main.

**Independent Test**: Triggering the AWS plan workflow via GitHub Actions dispatch with `account=dev`, `region=us-east-1`, `versionmesh=bluemesh` runs `terragrunt plan --all` against the correct directory path.

**Acceptance Scenarios**:

1. **Given** the justfile is updated with the new path pattern, **When** I run `just aws-plan dev us-east-1 bluemesh`, **Then** it executes `terragrunt plan --all` from `aws/dev/us-east-1/bluemesh/`.
2. **Given** GitHub Actions workflows use the new input parameters (account, region, versionmesh), **When** I dispatch `aws-kubernetes-plan.yaml` with `account=dev`, `region=us-east-1`, `cluster=bluemesh`, **Then** the workflow runs against the correct path.
3. **Given** the shared OIDC resources, **When** I run `just aws-apply-shared dev`, **Then** it targets `aws/dev/shared/oidc/` (shared resources now live under the account level, not nested under region).

---

### Edge Cases

- What happens if `deployment_code` tags conflict across accounts (e.g., both dev and stage have a `bluemesh`)? The tag value must include the account to ensure uniqueness.
- What happens to the old directory tree and any leftover state files after the restructure? They must be explicitly deleted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Repository MUST follow the `<provider>/<account>/<region>/<versionmesh>` directory pattern where account maps to an AWS account boundary (dev, stage, prod, cust1).
- **FR-002**: `root.hcl` MUST parse the new directory path to derive account, region, and versionmesh automatically — no manual input variables for these values.
- **FR-003**: Deployment versions MUST follow the `<version>mesh` naming convention (bluemesh, redmesh, greenmesh, etc.) replacing the current color-only naming (blue, green, kubeadm).
- **FR-004**: All EC2 instances in a deployment MUST be tagged with a `deployment_code` tag whose value uniquely identifies the deployment (combining versionmesh name, account, and region).
- **FR-005**: Instances MUST have IAM permissions to call `ec2:DescribeInstances` filtered by the `deployment_code` tag so they can discover peers programmatically.
- **FR-006**: The justfile MUST be updated to accept the new parameter pattern: `just aws-plan <account> <region> <versionmesh>`.
- **FR-007**: GitHub Actions workflows MUST be updated to use account/region/versionmesh inputs and resolve the correct directory path.
- **FR-008**: This is a greenfield implementation — all existing state files, OIDC roles, and account-level resources from the old layout MUST be deleted. No state migration.
- **FR-009**: The restructure MUST start with AWS only; GCP restructure is out of scope for this spec and will follow as a separate feature.

### Key Entities

- **Account**: Represents an AWS account boundary (dev, stage, prod, cust1). Maps to a specific AWS account ID and determines state backend, provider credentials, and OIDC trust scope.
- **Versionmesh**: A named deployment version within an account and region (e.g., bluemesh, redmesh). Each versionmesh is an independent infrastructure stack with its own VPC, instances, and state.
- **Deployment Code**: A unique tag value (`<versionmesh>-<account>-<region>`) applied to all resources in a deployment, enabling tag-based filtering and service discovery across EC2 instances.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All `terragrunt plan --all` commands succeed from the new directory structure with zero errors and correct provider/state configuration.
- **SC-002**: Any EC2 instance in a deployment can discover all peers by querying the `deployment_code` tag and receive accurate results within 5 seconds.
- **SC-003**: Old directory structure and state files are fully removed — no orphaned files remain after restructure.
- **SC-004**: GitHub Actions workflows successfully plan and apply against the new directory structure on first dispatch after the change.
- **SC-005**: A new deployment version (e.g., `redmesh`) can be created by duplicating a directory and adjusting inputs, taking under 10 minutes from copy to successful plan.

## Assumptions

- Only two AWS accounts currently exist: dev and stage. The pattern supports future accounts (prod, cust1) but only dev is implemented in this spec.
- The existing kubeadm module (`aws/terraform/modules/kubeadm/`) is reused as-is — this spec restructures the directory layout and adds tagging, not rewriting the module.
- This is a greenfield deployment — existing state, OIDC roles, and old directory structure will be deleted. No state migration needed.
- The `shared/` directory for admin-only resources (OIDC) lives under the account level: `aws/dev/shared/oidc/`.
- Route 53 DNS discovery remains alongside the new tag-based discovery — they are complementary, not replacements.
- GCP restructure will follow as a separate spec after AWS is validated.
