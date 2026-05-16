# Implementation Plan: Repository Restructure & VM Service Discovery

**Branch**: `001-repo-restructure-discovery` | **Date**: 2026-05-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/001-repo-restructure-discovery/spec.md`

## Summary

Restructure the AWS directory layout from `aws/us-east-1/compute-ansible/dev/kubeadm/` to `aws/dev/us-east-1/bluemesh/` (account-first, versionmesh naming). This is a greenfield implementation — existing state and old directory tree are deleted. Add `deployment_code` tag and IAM permissions for EC2 tag-based service discovery. Update `root.hcl`, justfile, and GitHub Actions to match the new path convention.

## Technical Context

**Language/Version**: HCL (Terraform 1.12.x, Terragrunt 0.81.x)
**Primary Dependencies**: `hashicorp/aws` provider ~> 6.44, `terraform-aws-modules/vpc/aws` ~> 6.4
**Storage**: S3 state backend (`compute-ansible-tg-state-{account}`) with native locking
**Testing**: `terragrunt plan --all` (zero-diff validation), `just validate` (module syntax)
**Target Platform**: AWS (`us-east-1`, account `317374277503`, profile `devops-compute-ansible`)
**Project Type**: Infrastructure as Code (Terragrunt monorepo)
**Constraints**: Zero long-lived credentials (OIDC only), admin-only `shared/` resources
**Scale/Scope**: 3 terragrunt units (oidc, vpc, ec2), 1 module to modify (kubeadm), 3 GH Actions workflows, 1 justfile

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | PASS | All changes are HCL/Terragrunt — no manual console work |
| II. Git-Driven Deployment | PASS | Changes flow through PR; `shared/` applied by admin locally |
| III. Directory-as-Contract | PASS — **MODIFIES** | This spec changes the contract from `<provider>/<region>/compute-ansible/<env>/<color>` to `<provider>/<account>/<region>/<versionmesh>`. Constitution must be amended after implementation. |
| IV. Spec-Driven Development | PASS | This is the SDD cycle |
| V. Automation via Just | PASS | Justfile updated with new recipe signatures |

**Post-implementation TODO**: Amend constitution Principle III to reflect the new path pattern.

## Project Structure

### Documentation (this feature)

```text
specs/001-repo-restructure-discovery/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── tasks.md
```

### Source Code (repository root)

```text
aws/
├── root.hcl                                  # MODIFIED: path_parts index swap
├── terraform/modules/
│   ├── kubeadm/                              # MODIFIED: deployment_code tag, IAM, IMDS
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── user-data.sh
│   ├── vpc/                                  # UNCHANGED
│   └── oidc/                                 # UNCHANGED
│
├── dev/                                      # NEW: account-first layout
│   ├── account.hcl                           # NEW: account_id, profile, cloud_provider
│   ├── shared/
│   │   └── oidc/terragrunt.hcl              # MOVED from us-east-1/compute-ansible/shared/oidc/
│   └── us-east-1/
│       ├── region.hcl                        # MOVED from us-east-1/region.hcl
│       └── bluemesh/
│           ├── vpc/terragrunt.hcl            # MOVED from dev/kubeadm/vpc/
│           └── ec2/terragrunt.hcl            # MOVED from dev/kubeadm/ec2/

├── us-east-1/                                # DELETED (old layout)
│   └── compute-ansible/                           # DELETED

.github/workflows/
├── aws-kubernetes-plan.yaml                  # MODIFIED: account input, region in just calls
├── aws-kubernetes-provision.yaml             # MODIFIED: same
└── aws-kubernetes-destroy.yaml               # MODIFIED: same

justfile                                      # MODIFIED: new recipe signatures with region param
bin/aws-connect.sh                            # MODIFIED: optional, new path convention
```

**Structure Decision**: Account-first layout. The `compute-ansible` directory level is removed — it was redundant since this is a single-application repo. `region.hcl` moves inside the account directory. A new `account.hcl` is introduced at the account level to hold account-specific config (account_id, profile) that was previously embedded in `region.hcl`.

## Phase 1 — Directory Restructure (US1 + US3)

### 1.1 New `root.hcl` Path Parsing

Current `path_relative_to_include()` for `aws/us-east-1/compute-ansible/dev/kubeadm/vpc/`:
```
split result: ["us-east-1", "compute-ansible", "dev", "kubeadm", "vpc"]
               [0]           [1]           [2]   [3]         [4]
```

New `path_relative_to_include()` for `aws/dev/us-east-1/bluemesh/vpc/`:
```
split result: ["dev", "us-east-1", "bluemesh", "vpc"]
               [0]    [1]          [2]          [3]
```

Changes to `aws/root.hcl`:
- `environment` (now `account`): `path_parts[2]` → `path_parts[0]`
- `region`: `path_parts[0]` → `path_parts[1]`
- `cluster_color` (now `versionmesh`): `path_parts[3]` → `path_parts[2]`
- Rename local `cluster_color` → `versionmesh` for clarity
- Rename local `environment` → `account` to match the new semantics
- Load `account.hcl` from parent folders (replaces account_id being in region.hcl)
- Load `region.hcl` from parent folders (now nested under account)

### 1.2 New `account.hcl`

Introduce `aws/dev/account.hcl`:
```hcl
locals {
  account    = "dev"
  account_id = "317374277503"
  profile    = "devops-compute-ansible"
}
```

This separates account-level config from region-level config. `region.hcl` now only holds region:
```hcl
locals {
  region = "us-east-1"
}
```

### 1.3 Shared Resources Path

`shared/oidc/` moves to `aws/dev/shared/oidc/`. The `root.hcl` must handle the `shared` case: when `path_parts[0]` is the account and `path_parts[1]` is `shared`, there is no region or versionmesh.

Path: `aws/dev/shared/oidc/` → `split: ["dev", "shared", "oidc"]`
- `account` = `path_parts[0]` = `dev`
- Check if `path_parts[1]` == `"shared"` → set `versionmesh = ""`, skip region loading

### 1.4 Justfile Updates

New recipe signatures add `region` parameter:
```
aws-plan account region versionmesh:
    cd aws/{{account}}/{{region}}/{{versionmesh}} && terragrunt plan --all --non-interactive

aws-apply-shared account:
    cd aws/{{account}}/shared && terragrunt apply --all --non-interactive
```

### 1.5 GitHub Actions Updates

Workflow inputs:
- Rename `environment` → `account` (or keep as `environment` with updated semantics)
- `cluster` input options: replace `blue`, `green`, `kubeadm` with `bluemesh` (extensible)
- Just calls: `just aws-plan ${{ env.ACCOUNT }} ${{ env.REGION }} ${{ env.CLUSTER }}`

### 1.6 Delete Old Directory Tree

Remove `aws/us-east-1/` entirely. All state in S3 from old runs is abandoned (greenfield).

## Phase 2 — Service Discovery (US2)

### 2.1 `deployment_code` Tag

Tag value format: `<versionmesh>-<account>-<region>` (e.g., `bluemesh-dev-us-east-1`).

Added as a Terraform variable `deployment_code` in the kubeadm module, passed from `root.hcl` common inputs or from the terragrunt.hcl:
```hcl
deployment_code = "${include.root.locals.versionmesh}-${include.root.locals.account}-${include.root.locals.region}"
```

Applied to:
- `aws_instance.control_plane` tags
- `aws_spot_instance_request.worker` tags
- `aws_ec2_tag` resources for spot tag propagation

### 2.2 IAM Policy for EC2 Discovery

Add inline policy to the existing SSM IAM role:
```hcl
resource "aws_iam_role_policy" "ec2_discovery" {
  name = "ec2-discovery"
  role = aws_iam_role.ssm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances", "ec2:DescribeTags"]
      Resource = "*"
    }]
  })
}
```

`ec2:DescribeInstances` and `ec2:DescribeTags` do not support resource-level permissions — `Resource = "*"` is required. These are read-only actions.

### 2.3 IMDS Instance Tags

Enable instance metadata tags on both instance types:
```hcl
metadata_options {
  http_endpoint          = "enabled"
  http_tokens            = "required"    # IMDSv2
  instance_metadata_tags = "enabled"
}
```

This also fixes a latent bug: `user-data.sh` line 65 calls `aws ec2 describe-tags` to read the instance's own Name tag, but the SSM role lacks `ec2:DescribeTags` permission. With IMDS tags enabled, the hostname code can use the local metadata endpoint instead of the EC2 API.

### 2.4 User-Data Peer Discovery

Update `user-data.sh` to:
1. Read own tags via IMDS (hostname, role, deployment_code) — no IAM needed
2. Discover peers via `aws ec2 describe-instances --filters "Name=tag:deployment_code,Values=$DEPLOYMENT_CODE"` — requires IAM policy from 2.2
3. Write discovered peers to `/etc/compute-ansible/peers.json` for consumption by kubeadm bootstrap or other tooling
4. Include a retry loop (peers may boot simultaneously)

### 2.5 Tag Propagation for Spot Instances

Add `aws_ec2_tag.worker_deployment_code` resource to propagate the `deployment_code` tag to spot instances (spot requests don't auto-propagate tags to the instance).

## Complexity Tracking

No constitution violations to justify. The change to Principle III (directory pattern) is an intentional evolution, not a violation — the principle will be amended post-implementation.
