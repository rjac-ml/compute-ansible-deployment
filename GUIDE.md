# Compute-Ansible Machines Infrastructure Guide

A step-by-step guide for provisioning Kubernetes clusters on AWS (EKS) and GCP (GKE) using the Terragrunt modules in this repository. Covers local development setup, manual deployments, and GitHub Actions CI/CD.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository Layout](#2-repository-layout)
3. [How Terragrunt Works Here](#3-how-terragrunt-works-here)
4. [Just Command Reference](#4-just-command-reference)
5. [AWS — Local Setup and Deployment](#5-aws--local-setup-and-deployment)
6. [GCP — Local Setup and Deployment](#6-gcp--local-setup-and-deployment)
7. [GitHub Actions CI/CD](#7-github-actions-cicd)
8. [Security Model](#8-security-model)
9. [Day-2 Operations](#9-day-2-operations)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

### Required Tools

| Tool | Version | Install |
|------|---------|---------|
| **Terraform** | >= 1.12.x | [terraform.io/downloads](https://developer.hashicorp.com/terraform/install) |
| **Terragrunt** | >= 0.81.x | [terragrunt.gruntwork.io](https://terragrunt.gruntwork.io/docs/getting-started/install/) |
| **kubectl** | latest | [kubernetes.io/docs](https://kubernetes.io/docs/tasks/tools/) |
| **just** | latest | [github.com/casey/just](https://github.com/casey/just) |

### AWS-Specific

| Tool | Version | Install |
|------|---------|---------|
| **AWS CLI** | >= 2.x | [docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |

You need an AWS profile named `devops-compute-ansible` configured:

```bash
# Configure the profile
aws configure --profile devops-compute-ansible
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity --profile devops-compute-ansible
```

### GCP-Specific

| Tool | Version | Install |
|------|---------|---------|
| **gcloud CLI** | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |

You need Application Default Credentials (ADC) configured:

```bash
# Authenticate
gcloud auth login
gcloud auth application-default login

# Set the project
gcloud config set project TBD

# Verify
gcloud projects describe TBD
```

> **Note**: Install gcloud via the official tarball, not Homebrew. Homebrew installs may have path issues with Terraform provider plugins.

---

## 2. Repository Layout

```
compute-ansible-machines/
├── aws/                          # AWS infrastructure
│   ├── root.hcl                  # Terragrunt root (S3 backend, AWS provider)
│   ├── terraform/modules/        # Terraform modules (vpc, eks, general, identity, oidc, kubeadm, roles)
│   └── us-east-1/compute-ansible/    # Regional deployments
│       ├── shared/oidc/          # GitHub OIDC provider (admin-only, once)
│       ├── dev/blue/             # Dev blue EKS: vpc → eks → general
│       ├── dev/green/            # Dev green EKS: vpc → eks (standard VPC CNI)
│       ├── dev/kubeadm/          # Dev kubeadm lab: vpc → ec2 (2 CP + 2 workers)
│       └── prod/blue/            # Prod blue: vpc → roles → eks → general
│
├── gcp/                          # GCP infrastructure
│   ├── root.hcl                  # Terragrunt root (GCS backend, Google provider)
│   ├── terraform/modules/        # Terraform modules (vpc, gke, general, wif)
│   └── us-central1/compute-ansible/  # Regional deployments
│       ├── shared/wif/           # Workload Identity Federation (admin-only, once)
│       └── dev/blue/             # Dev blue: vpc → gke → general
│
├── bin/                          # Helper scripts
│   ├── aws-connect.sh            # Connect kubectl to EKS
│   └── gcp-connect.sh            # Connect kubectl to GKE
│
├── justfile                      # Command runner — all operations go through here
│
└── .github/workflows/            # CI/CD pipelines (plan, provision, destroy)
```

Each cloud follows the **directory-as-contract** pattern:

```
<provider>/<region>/compute-ansible/<environment>/<color>/<component>
```

The `root.hcl` in each provider directory parses this path to automatically derive the environment, region, and provider configuration. You never set these manually.

---

## 3. How Terragrunt Works Here

### What `root.hcl` Does

Each provider has a `root.hcl` that every component includes. It handles three things automatically:

1. **Provider generation** — writes a `provider.tf` with the correct credentials, region, and tags/labels
2. **State backend** — configures remote state (S3 for AWS, GCS for GCP) with per-environment isolation
3. **Common inputs** — passes `region`, `environment`, and tagging to every module

### Dependency Chain

Components depend on each other via Terragrunt `dependency` blocks:

```
shared/ (admin deploys once, manually)
│
└── dev/blue/ or prod/blue/ (CI/CD or developer deploys)
    ├── vpc           ← no dependencies
    │   └── eks/gke   ← depends on vpc
    │       └── general ← depends on eks/gke
    └── roles         ← (prod AWS only, no dependencies)
```

When you run `terragrunt apply --all`, Terragrunt resolves these automatically in the correct order.

### State Backends

| Provider | Bucket Pattern | Locking |
|----------|---------------|---------|
| AWS | `compute-ansible-tg-state-{env}` (e.g., `compute-ansible-tg-state-dev`) | S3 native (TF 1.10+) |
| GCP | `compute-ansible-tg-state-gcp-{env}` (e.g., `compute-ansible-tg-state-gcp-dev`) | GCS built-in |

GCS buckets are auto-created by Terragrunt. AWS S3 buckets must exist beforehand.

---

## 4. Just Command Reference

All infrastructure operations go through `just` recipes. Run `just --list` to see all available commands.

### Quick Reference

| Command | What It Does |
|---------|-------------|
| `just aws-plan dev blue` | Dry-run the dev blue EKS cluster (vpc + eks + general) |
| `just aws-apply dev blue` | Deploy the dev blue EKS cluster |
| `just aws-destroy dev blue` | Tear down the dev blue EKS cluster |
| `just aws-plan dev green` | Dry-run the dev green EKS cluster |
| `just aws-apply dev green` | Deploy the dev green EKS cluster |
| `just aws-plan dev kubeadm` | Dry-run the kubeadm EC2 lab (vpc + ec2) |
| `just aws-apply dev kubeadm` | Deploy the kubeadm EC2 lab |
| `just aws-destroy dev kubeadm` | Tear down the kubeadm lab |
| `just aws-plan-shared shared` | Dry-run shared resources (OIDC) |
| `just aws-apply-shared shared` | Deploy shared resources (admin-only) |
| `just gcp-plan dev blue` | Dry-run the GCP dev blue GKE cluster |
| `just gcp-apply dev blue` | Deploy the GCP dev blue GKE cluster |
| `just gcp-destroy dev blue` | Tear down the GCP dev blue GKE cluster |
| `just gcp-apply-shared dev` | Deploy GCP shared resources (WIF, admin-only) |
| `just aws-ssm dev kubeadm cp-1` | SSH into kubeadm control-plane 1 via SSM |
| `just aws-sync-oidc-secret dev` | Push OIDC role ARN to GitHub secret `GH_ROLE_DEV` |
| `just fmt` | Format all Terraform files |
| `just validate` | Validate all Terraform modules |
| `just check-rename` | Check for leftover pixemilar references |

### 4.1 AWS EKS Clusters (blue / green)

The `env` and `color` arguments map directly to the directory path: `aws/us-east-1/compute-ansible/<env>/<color>/`.

```bash
# Plan first (always)
just aws-plan dev blue

# Apply
just aws-apply dev blue

# Destroy
just aws-destroy dev blue
```

The same pattern works for the green cluster — replace `blue` with `green`:

```bash
just aws-plan dev green
just aws-apply dev green
```

**Blue vs Green:** Both are independent EKS clusters with their own VPC, node groups, and state. Blue is the primary cluster with post-cluster addons (general/). Green uses standard VPC CNI with no additional Helm charts.

### 4.2 AWS Kubeadm Lab

The kubeadm lab uses `kubeadm` as the color argument. It deploys a separate VPC + EC2 instances (2 on-demand control planes + 2 spot workers).

```bash
# Plan
just aws-plan dev kubeadm

# Apply
just aws-apply dev kubeadm

# Destroy
just aws-destroy dev kubeadm
```

After deploying, connect to instances via SSM:

```bash
# Connect to control-plane 1
just aws-ssm dev kubeadm cp-1

# Connect to control-plane 2
just aws-ssm dev kubeadm cp-2

# Connect to worker 1
just aws-ssm dev kubeadm worker-1

# Connect to worker 2
just aws-ssm dev kubeadm worker-2
```

The kubeadm lab includes a Route 53 private hosted zone (`kubeadm.compute-ansible.internal`) so instances resolve each other by name (e.g., `cp-1.kubeadm.compute-ansible.internal`).

### 4.3 AWS Shared Resources (Admin-Only)

Shared resources (OIDC provider, CI/CD IAM role) live under `shared/` and must be applied by an admin — CI/CD cannot modify its own trust policy.

```bash
# Plan shared resources
just aws-plan-shared shared

# Apply shared resources
just aws-apply-shared shared
```

After applying, sync the OIDC role ARN to GitHub:

```bash
# Pushes the role ARN to GitHub secret GH_ROLE_DEV
just aws-sync-oidc-secret dev
```

### 4.4 GCP Clusters

```bash
just gcp-plan dev blue
just gcp-apply dev blue
just gcp-destroy dev blue
```

GCP shared resources (WIF):

```bash
just gcp-apply-shared dev
```

### 4.5 Validation and Formatting

```bash
# Format all .tf files across aws/ and gcp/
just fmt

# Validate all Terraform modules (init + validate, no backend)
just validate

# Check for leftover pixemilar references (rename audit)
just check-rename
```

### 4.6 Init (First-Time or After Cache Clear)

If you clear `.terragrunt-cache` or clone fresh, init downloads providers and modules:

```bash
just aws-init dev blue
```

---

## 5. AWS — Local Setup and Deployment

### 5.1 One-Time Setup: GitHub OIDC Provider

The `shared/oidc` component creates the GitHub OIDC provider and CI/CD IAM role. This is **admin-only** and done once per AWS account:

```bash
cd aws/us-east-1/compute-ansible/shared/oidc
terragrunt apply
```

This outputs the `cicd_role_arn` that GitHub Actions will assume.

### 5.2 Deploy an EKS Environment (blue / green)

**Deploy everything at once** (using just recipes):

```bash
just aws-plan dev blue    # dry run first
just aws-apply dev blue   # deploy
```

**Or deploy component by component** (useful for debugging):

```bash
# Step 1: Network
cd aws/us-east-1/compute-ansible/dev/blue/vpc
terragrunt apply

# Step 2: Kubernetes cluster
cd aws/us-east-1/compute-ansible/dev/blue/eks
terragrunt apply

# Step 3: Post-cluster components (LBC, Secrets CSI)
cd aws/us-east-1/compute-ansible/dev/blue/general
terragrunt apply
```

The green cluster follows the same pattern (`just aws-apply dev green`). Green has vpc + eks only (no general/ directory).

### 5.3 Deploy the Kubeadm Lab

The kubeadm lab is a self-managed Kubernetes environment on EC2, separate from EKS:

```bash
just aws-plan dev kubeadm    # dry run
just aws-apply dev kubeadm   # deploy (vpc + ec2)
```

This creates 2 on-demand control plane instances and 2 spot worker instances in a dedicated VPC (10.2.0.0/16), with a Route 53 private hosted zone for internal DNS.

**Access instances via SSM** (no SSH keys needed):

```bash
just aws-ssm dev kubeadm cp-1       # control-plane 1
just aws-ssm dev kubeadm cp-2       # control-plane 2
just aws-ssm dev kubeadm worker-1   # worker 1
just aws-ssm dev kubeadm worker-2   # worker 2
```

**Internal DNS:** Instances resolve each other at `<name>.kubeadm.compute-ansible.internal` (e.g., `cp-1.kubeadm.compute-ansible.internal`). DNS is toggled via `enable_dns` in the terragrunt.hcl.

### 5.4 Connect to an EKS Cluster

```bash
# Using the helper script (recommended)
./bin/aws-connect.sh dev blue admin       # Connect as admin
./bin/aws-connect.sh dev blue developer   # Connect as developer

# Or manually
aws eks update-kubeconfig \
  --name compute-ansible-dev-blue \
  --role-arn arn:aws:iam::317374277503:role/compute-ansible-dev-blue-admin \
  --profile devops-compute-ansible

kubectl get nodes
```

### 5.5 Plan Changes (Dry Run)

```bash
just aws-plan dev blue      # EKS blue
just aws-plan dev green     # EKS green
just aws-plan dev kubeadm   # Kubeadm lab
```

### 5.6 Destroy an Environment

```bash
just aws-destroy dev blue      # EKS blue
just aws-destroy dev green     # EKS green
just aws-destroy dev kubeadm   # Kubeadm lab
```

> **Warning**: Destroy tears down the VPC and all resources within the cluster path. The `shared/oidc` component is not affected (it lives outside the environment path).

### AWS Modules Summary

| Module | What It Creates | Key Inputs |
|--------|----------------|------------|
| **vpc** | VPC, public/private subnets, NAT Gateway, secondary CIDR (100.64.0.0/16) for pods, VPC endpoints | `name`, `environment` |
| **eks** | EKS cluster, managed node groups (`compute-ansible-core` on-demand, `compute-ansible-compute` spot), admin/developer IAM roles, EKS access entries | `cluster_version`, `vpc_id`, `private_subnets`, `eks_managed_node_groups`, `cicd_role_arn` |
| **general** | AWS Load Balancer Controller (Helm), ASCP Secrets Store CSI (Helm), Pod Identity associations | `cluster_name`, `cluster_endpoint`, `vpc_id`, `enable_*` toggles |
| **identity** | Pod Identity bindings for service accounts | `cluster_name`, service account configs |
| **kubeadm** | EC2 instances (on-demand CPs + spot workers), SSM IAM role, security group, EBS data volumes, Route 53 private DNS | `name`, `environment`, `vpc_id`, `private_subnets`, `kubernetes_version`, `enable_dns` |
| **oidc** | GitHub OIDC provider + CI/CD IAM role | `github_org`, `github_repo_prefix` |
| **roles** | Admin + CI/CD IAM roles (prod lifecycle) | `cluster_name` |

---

## 6. GCP — Local Setup and Deployment

### 6.1 One-Time Setup: Workload Identity Federation

The `shared/wif` component creates the WIF pool, OIDC provider, and CI/CD service account. This is **admin-only** and done once per GCP project:

```bash
cd gcp/us-central1/compute-ansible/shared/wif
terragrunt apply
```

This outputs the `wif_provider_name` and `service_account_email` needed for GitHub Actions.

### 6.2 Deploy an Environment

**Deploy everything at once**:

```bash
just gcp-plan dev blue    # dry run first
just gcp-apply dev blue   # deploy
```

**Or component by component**:

```bash
# Step 1: Network
cd gcp/us-central1/compute-ansible/dev/blue/vpc
terragrunt apply

# Step 2: Kubernetes cluster
cd gcp/us-central1/compute-ansible/dev/blue/gke
terragrunt apply

# Step 3: Post-cluster components (Secrets Store CSI)
cd gcp/us-central1/compute-ansible/dev/blue/general
terragrunt apply
```

### 6.3 Connect to the Cluster

```bash
# Using the helper script (recommended)
./bin/gcp-connect.sh dev blue              # Connect to dev blue (us-central1)
./bin/gcp-connect.sh dev blue us-central1  # Explicit region

# Or manually
gcloud container clusters get-credentials compute-ansible-dev-blue \
  --region us-central1 \
  --project TBD

kubectl get nodes
```

### 6.4 Plan Changes (Dry Run)

```bash
just gcp-plan dev blue
```

### 6.5 Destroy an Environment

```bash
just gcp-destroy dev blue
```

### GCP Modules Summary

| Module | What It Creates | Key Inputs |
|--------|----------------|------------|
| **vpc** | VPC network, private subnet with Private Google Access, secondary ranges for pods (100.64.0.0/16) and services (100.65.0.0/20), Cloud Router + Cloud NAT | `name`, `environment`, `subnet_ip`, `pods_range_cidr`, `services_range_cidr` |
| **gke** | GKE private cluster (Workload Identity, Gateway API, DNS caching), two node pools (`compute-ansible-core` on-demand, `compute-ansible-compute` spot), IAM bindings for admin/developer/CI-CD | `kubernetes_version`, `network_name`, `subnetwork_name`, `node_pools`, `cicd_service_account_email` |
| **general** | Secrets Store CSI Driver (Helm v1.5.5) + GCP Secret Manager provider (K8s manifests v1.6.2) | `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`, `enable_secrets_store_csi` |
| **wif** | WIF pool + OIDC provider, CI/CD service account, IAM bindings (container.admin, compute.admin, etc.) | `github_org`, `github_repo_prefix`, `service_account_id` |

### GCP vs AWS: What's Different

GKE is simpler than EKS because many components are built-in:

| Concern | AWS (EKS) | GCP (GKE) |
|---------|-----------|-----------|
| Load balancer | AWS LBC Helm chart required | Built-in (`http_load_balancing`) |
| CNI / DNS / metrics | Separate EKS addons (vpc-cni, coredns, metrics-server) | Built-in |
| Pod-to-IAM mapping | Pod Identity module + associations | Workload Identity (cluster-level toggle) |
| Secrets CSI | ASCP v2.x (bundles CSI driver) | CSI driver (Helm) + GCP provider (K8s manifests, separate) |
| CI/CD auth | GitHub OIDC -> IAM Role (assume-role) | GitHub OIDC -> WIF -> Service Account (impersonation) |

---

## 7. GitHub Actions CI/CD

### 7.1 How It Works

All workflows are **manual dispatch** (`workflow_dispatch`) — you trigger them from the GitHub Actions UI, selecting the environment, color, and region.

Each workflow:
1. Checks out the repo
2. Authenticates with the cloud provider via OIDC (no long-lived credentials)
3. Installs Terraform 1.12.2 + Terragrunt 0.81.10
4. Runs the terragrunt command against `<provider>/<region>/compute-ansible/<environment>/<color>/`

### 7.2 Available Workflows

| Workflow | File | Action |
|----------|------|--------|
| AWS Plan | `aws-kubernetes-plan.yaml` | `terragrunt plan --all` (dry run) |
| AWS Provision | `aws-kubernetes-provision.yaml` | `terragrunt apply --all` (deploy) |
| AWS Destroy | `aws-kubernetes-destroy.yaml` | `terragrunt destroy --all` (teardown) |
| GCP Plan | `gcp-kubernetes-plan.yaml` | `terragrunt plan --all` (dry run) |
| GCP Provision | `gcp-kubernetes-provision.yaml` | `terragrunt apply --all` (deploy) |
| GCP Destroy | `gcp-kubernetes-destroy.yaml` | `terragrunt destroy --all` (teardown) |

### 7.3 AWS — Required GitHub Secrets

| Secret | Value | How to Get It |
|--------|-------|---------------|
| `GH_ROLE_NEXT_SIGNAL` | IAM role ARN for GitHub Actions | Output of `shared/oidc`: `arn:aws:iam::317374277503:role/next-signal-github-actions` |

The workflow creates a temporary AWS profile named `devops-compute-ansible` using the OIDC session credentials, so the Terragrunt `root.hcl` (which references `profile = "devops-compute-ansible"`) works identically in CI and locally.

### 7.4 GCP — Required GitHub Secrets

| Secret | Value | How to Get It |
|--------|-------|---------------|
| `GCP_WIF_PROVIDER_DEV` | WIF provider name (dev) | Output of `shared/wif`: `terragrunt output wif_provider_name` |
| `GCP_WIF_PROVIDER_PROD` | WIF provider name (prod) | Same, from prod's WIF if deployed |
| `GCP_SERVICE_ACCOUNT_DEV` | CI/CD service account (dev) | Output of `shared/wif`: `terragrunt output service_account_email` |
| `GCP_SERVICE_ACCOUNT_PROD` | CI/CD service account (prod) | Same, from prod's WIF if deployed |

> **Note**: `PROJECT_ID` (`TBD`) is hardcoded in the workflow files -- it's not sensitive and doesn't need to be a GitHub Secret.

The workflow uses `google-github-actions/auth@v2` to exchange the GitHub OIDC token for GCP credentials via Workload Identity Federation.

### 7.5 Setting Up CI/CD From Scratch

**AWS**:

```bash
# 1. Deploy the OIDC provider (admin, local)
cd aws/us-east-1/compute-ansible/shared/oidc
terragrunt apply

# 2. Get the role ARN
terragrunt output cicd_role_arn
# → arn:aws:iam::317374277503:role/next-signal-github-actions

# 3. Add to GitHub repo settings → Secrets → Actions:
#    GH_ROLE_NEXT_SIGNAL = <the ARN above>
```

**GCP**:

```bash
# 1. Deploy WIF (admin, local)
cd gcp/us-central1/compute-ansible/shared/wif
terragrunt apply

# 2. Get the outputs
terragrunt output wif_provider_name
# → projects/123456/locations/global/workloadIdentityPools/next-signal-github/providers/next-signal-github-provider

terragrunt output service_account_email
# → next-signal-github-actions@TBD.iam.gserviceaccount.com

# 3. Add to GitHub repo settings → Secrets → Actions:
#    GCP_WIF_PROVIDER_DEV = <wif_provider_name output>
#    GCP_SERVICE_ACCOUNT_DEV = <service_account_email output>
```

### 7.6 Critical CI/CD Configuration

The workflows include these settings that **must not be changed**:

```yaml
# In setup-terraform step — wrapper corrupts Terragrunt's JSON parsing
- uses: hashicorp/setup-terraform@v3
  with:
    terraform_wrapper: false    # REQUIRED

# Permissions — OIDC token exchange needs id-token: write
permissions:
  id-token: write
  contents: read
```

---

## 8. Security Model

### No Long-Lived Credentials

This repository uses **zero static credentials** for CI/CD:

- **AWS**: GitHub OIDC token exchange -> IAM role assumption (short-lived STS session)
- **GCP**: GitHub OIDC token exchange -> Workload Identity Federation -> Service Account impersonation (short-lived access token)

No AWS access keys or GCP service account JSON keys exist anywhere -- not in GitHub Secrets, not in config files.

### Trust Boundaries

**AWS OIDC trust** (`aws/terraform/modules/oidc/`):
- The CI/CD role can only be assumed by GitHub Actions workflows from repos matching `repo:next-signal/compute-ansible-*:ref:refs/heads/main` or `repo:next-signal/compute-ansible-*:ref:refs/heads/test/*` -- both `main` and `test/*` branches can trigger deployments
- The audience must be `sts.amazonaws.com` (standard GitHub OIDC)

**GCP WIF trust** (`gcp/terraform/modules/wif/`):
- The WIF pool only issues tokens when `repository_owner == 'next-signal'` AND the repo name starts with `next-signal/compute-ansible` (pool-level `attribute_condition`)
- Service account impersonation allows all pool identities (`/*`) because GCP `principalSet` does not support wildcards in attribute values
- Security is enforced at the pool level -- repos that don't match the `attribute_condition` can't get a pool token in the first place

### What Each CI/CD Identity Can Do

| Provider | Identity | Permissions | Scope |
|----------|----------|-------------|-------|
| AWS | `next-signal-github-actions` role | EKS, EC2, ELB, IAM (roles/policies/groups), KMS, CloudWatch Logs, S3 (state buckets) | Scoped to `us-east-1` + account (IAM is account-wide) |
| GCP | `next-signal-github-actions` SA | `container.admin`, `compute.admin`, `iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `storage.admin`, custom `cicdIamBindingManager` (IAM policy get/set only) | Project-wide |

### Human Access (AWS)

Human access to EKS clusters uses **IAM role assumption**, not direct credentials:

```
IAM User -> IAM Group (compute-ansible-dev-blue-admin) -> AssumeRole -> compute-ansible-dev-blue-admin role -> EKS access entry
```

- **Admin role**: `AmazonEKSClusterAdminPolicy` (cluster-scoped)
- **Developer role**: `AmazonEKSEditPolicy` (all namespaces)
- Roles trust the account root principal -- access is controlled by group membership

### Human Access (GCP)

GCP uses native IAM bindings on the GKE cluster (configured in the `gke` module). Access is granted via `gcloud container clusters get-credentials`.

### Admin-Only Resources

The `shared/` directory contains account-level resources that **cannot be deployed by CI/CD**:

| Provider | Component | What It Creates |
|----------|-----------|----------------|
| AWS | `shared/oidc/` | GitHub OIDC provider + CI/CD role |
| GCP | `shared/wif/` | WIF pool + OIDC provider + CI/CD service account |

These must be applied manually by an administrator with appropriate access. This prevents CI/CD from modifying its own trust policy.

### State Isolation

Each environment has its own state backend -- `dev` workflows cannot read or write `prod` state:

- AWS: `compute-ansible-tg-state-dev` vs `compute-ansible-tg-state-prod` (separate S3 buckets)
- GCP: `compute-ansible-tg-state-gcp-dev` vs `compute-ansible-tg-state-gcp-prod` (separate GCS buckets)

---

## 9. Day-2 Operations

### Adding a New Environment (e.g., `prod`)

Create the directory structure mirroring `dev/`:

```bash
# AWS
mkdir -p aws/us-east-1/compute-ansible/prod/blue/{vpc,eks,general}

# GCP
mkdir -p gcp/us-central1/compute-ansible/prod/blue/{vpc,gke,general}
```

Copy the `terragrunt.hcl` files from `dev/blue/` and adjust inputs (instance sizes, node counts, etc.). The `root.hcl` will automatically derive `environment = "prod"` from the path.

### Adding a New Region

```bash
# Example: AWS eu-west-1
mkdir -p aws/eu-west-1/compute-ansible/dev/blue/{vpc,eks,general}

# Create region.hcl
cat > aws/eu-west-1/region.hcl << 'EOF'
locals {
  region     = "eu-west-1"
  account_id = "317374277503"
  profile    = "devops-compute-ansible"
}
EOF
```

The `root.hcl` will pick up the new region automatically.

### Modifying Node Pools

Edit the environment's `terragrunt.hcl` for the cluster component:

- **AWS**: `aws/<region>/compute-ansible/<env>/<color>/eks/terragrunt.hcl` -- modify `eks_managed_node_groups`
- **GCP**: `gcp/<region>/compute-ansible/<env>/<color>/gke/terragrunt.hcl` -- modify `node_pools`

Then apply:

```bash
cd <provider>/<region>/compute-ansible/<env>/<color>/eks  # or gke
terragrunt plan    # review changes
terragrunt apply   # apply
```

### Upgrading Kubernetes Version

Update `cluster_version` (AWS) or `kubernetes_version` (GCP) in the cluster's `terragrunt.hcl`:

```hcl
# AWS (eks/terragrunt.hcl)
cluster_version = "1.35"

# GCP (gke/terragrunt.hcl)
kubernetes_version = "1.35"
```

---

## 10. Troubleshooting

### "Could not load plugin" or provider errors

```bash
# Clear Terragrunt cache and re-init
cd <component-dir>
rm -rf .terragrunt-cache
terragrunt init
```

### "Failed to decode base64 data (sensitive value)"

This happens when Terraform's `base64decode()` receives a sensitive-marked value. The modules already handle this with `nonsensitive()`, but if you see it in a new module:

```hcl
# Wrong
base64decode(var.cluster_ca_certificate)

# Correct
base64decode(nonsensitive(var.cluster_ca_certificate))
```

### State lock errors

Someone else (or a previous run) may hold the lock:

```bash
# Check who holds the lock, then if safe:
terragrunt force-unlock <LOCK_ID>
```

### "run-all is deprecated"

Use the new syntax:

```bash
# Old (deprecated)
terragrunt run-all apply

# New
terragrunt apply --all --non-interactive
```

### AWS: "The security token included in the request is expired"

Re-authenticate:

```bash
aws sso login --profile devops-compute-ansible
# or re-run aws configure --profile devops-compute-ansible
```

### GCP: "Could not find default credentials"

Re-authenticate:

```bash
gcloud auth application-default login
```

### GitHub Actions: Terragrunt output parsing failures

Ensure `terraform_wrapper: false` is set in the `setup-terraform` step. The wrapper injects GitHub annotations into stdout, corrupting Terragrunt's `terraform output -json` parsing.

### Dependency mock output mismatches

If you see errors like "output X not found" during `--all` runs, check that the `mock_outputs` in the dependent `terragrunt.hcl` match the actual outputs of the upstream module.
