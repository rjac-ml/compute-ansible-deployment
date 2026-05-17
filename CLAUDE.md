# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Multi-cloud IaC repository provisioning Kubernetes clusters (EKS, GKE, kubeadm) on AWS and GCP using **Terraform 1.12.x** and **Terragrunt 0.81.x**. The repo manages the full lifecycle: VPC/networking, cluster creation, post-cluster addons (LBC, Secrets CSI), CI/CD identity (OIDC/WIF), and a bare-metal kubeadm EC2 lab.

## Commands

All operations go through `just`. Claude cannot run `make`, `terragrunt`, or `terraform` commands directly — delegate those to the user.

```bash
just --list                        # Show all recipes
just fmt                           # Format all .tf files (aws/ + gcp/)
just validate                      # Init + validate every module (no backend)
just check-rename                  # Audit for stale "pixemilar" references

# AWS
just aws-plan dev us-east-1 bluemesh       # Plan bluemesh cluster
just aws-apply dev us-east-1 bluemesh      # Apply bluemesh cluster
just aws-destroy dev us-east-1 bluemesh    # Destroy bluemesh cluster
just aws-init dev us-east-1 bluemesh       # Download providers (fresh clone)
just aws-plan-shared dev                   # Plan admin-only OIDC resources
just aws-apply-shared dev                  # Apply admin-only OIDC resources
just aws-ssm dev us-east-1 bluemesh cp-1   # SSM into instance

# GCP
just gcp-plan dev blue             # Plan GKE blue cluster
just gcp-apply dev blue            # Apply GKE blue cluster
just gcp-destroy dev blue          # Destroy GKE blue cluster
just gcp-apply-shared dev          # Apply admin-only WIF resources

# Cluster access
./bin/aws-connect.sh dev bluemesh admin
./bin/gcp-connect.sh dev blue
```

## Architecture

### Directory-as-Contract

The directory path encodes the full deployment topology — `root.hcl` parses it to derive provider config, account, region, and state backend automatically:

```
<provider>/<account>/<region>/<versionmesh>/<component>/terragrunt.hcl
```

- `account` = AWS account boundary (dev, stage, prod). Config in `account.hcl`.
- `versionmesh` = deployment version (bluemesh, redmesh, etc.). Replaces old color naming.
- `shared/` resources: `<provider>/<account>/shared/<component>/` (no region/versionmesh).

Never hardcode account/region in terragrunt.hcl inputs — they come from the path.

### Module Layout

```
aws/
  root.hcl                          # S3 backend, AWS provider, common inputs
  terraform/modules/
    vpc/        eks/        general/       # Standard EKS stack
    identity/   oidc/       roles/         # IAM / CI/CD identity
    ec2-extended/  general-cilium/         # EC2 lab, Cilium variant
  dev/                                     # Account: dev
    account.hcl                            # Account ID, profile
    shared/oidc/                           # Admin-only (GitHub OIDC provider)
    us-east-1/                             # Region
      region.hcl
      bluemesh/{vpc,ec2}/                  # Versionmesh deployment

gcp/
  root.hcl                          # GCS backend, Google provider, common inputs
  terraform/modules/
    vpc/   gke/   general/   wif/
  us-central1/compute-ansible/
    shared/wif/                            # Admin-only (WIF pool)
    dev/{vpc,gke,general}/                 # Dev environment (pending restructure)
```

### Dependency Chain

Components within an environment depend on each other via Terragrunt `dependency` blocks. `terragrunt apply --all` resolves order automatically:

```
shared/ (admin-only, manual, once)
└── <account>/<region>/<versionmesh>/
    ├── vpc           ← no deps
    │   └── eks/gke/ec2 ← depends on vpc
    │       └── general ← depends on eks/gke
    └── roles         ← (prod AWS only)
```

### State Backends

Per-environment isolation — dev workflows cannot touch prod state:

| Provider | Pattern | Locking |
|----------|---------|---------|
| AWS | `compute-ansible-tg-state-{account}` (S3) | Native (TF 1.10+) |
| GCP | `compute-ansible-tg-state-gcp-{env}` (GCS) | Built-in |

### CI/CD Security

Zero long-lived credentials. GitHub Actions authenticate via OIDC token exchange:
- **AWS**: OIDC -> IAM role `next-signal-github-actions` (STS session). Trust scoped to `main` and `test/*` branches.
- **GCP**: OIDC -> WIF pool -> SA impersonation. Pool-level `attribute_condition` enforces org + repo prefix.
- `shared/` resources (OIDC, WIF) are admin-only — CI/CD cannot modify its own trust policy.

## HCL Conventions

- Run `just fmt` before committing any `.tf` changes.
- Use `terragrunt <cmd> --all --non-interactive` — `run-all` is deprecated.
- `terraform_wrapper: false` is required in CI/CD `setup-terraform` steps (wrapper corrupts JSON output).
- For `base64decode()` on sensitive values: `base64decode(nonsensitive(var.ca_cert))`.
- AWS account ID comes from `account.hcl` — never use `get_aws_account_id()` (runs before provider config).
- `mock_outputs` in terragrunt.hcl must match the actual outputs of the upstream module.
- GCP `principalSet` does NOT support wildcards — enforce repo scoping at the WIF pool level via `attribute_condition`.
- ASCP v2.x bundles the CSI driver on AWS — do not install `secrets-store-csi-driver` separately. On GCP, CSI driver and provider are two separate installs.

## Adding Infrastructure

**New account**: Create `<provider>/<account>/account.hcl` with account_id and profile, then add region directories under it.

**New region**: Create `<provider>/<account>/<region>/region.hcl` with region name, then add versionmesh directories under it.

**New versionmesh**: Copy an existing `<versionmesh>/` directory, adjust inputs. `root.hcl` derives account/region/versionmesh from path automatically.

**New module**: Add to `<provider>/terraform/modules/<name>/`, reference via `terraform.source` in the consumer's `terragrunt.hcl`, wire dependencies with `dependency` blocks and `mock_outputs`.

## Active Technologies
- HCL (Terraform 1.12.x, Terragrunt 0.81.x) + `hashicorp/aws` provider ~> 6.44, `terraform-aws-modules/vpc/aws` ~> 6.4 (001-repo-restructure-discovery)
- S3 state backend (`compute-ansible-tg-state-{account}`) with native locking (001-repo-restructure-discovery)
- Ansible 2.17.x (control side, on GitHub Actions); shell-installable Linux on hosts (Amazon Linux 2023 + Ubuntu LTS supported by AMI choice in `ec2-extended`) + `amazon.aws==10.*` collection, `boto3>=1.34`, `botocore>=1.34`, AWS Session Manager Plugin (003-ansible-node-exporter)
- One small S3 bucket per (env, region) for SSM file transfer (new, provisioned by Terragrunt). No persisted application data. (003-ansible-node-exporter)

## Recent Changes
- 001-repo-restructure-discovery: Added HCL (Terraform 1.12.x, Terragrunt 0.81.x) + `hashicorp/aws` provider ~> 6.44, `terraform-aws-modules/vpc/aws` ~> 6.4
