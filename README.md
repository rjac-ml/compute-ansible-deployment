# Compute-Ansible Machines Infrastructure

Multi-cloud Infrastructure as Code (IaC) repository for provisioning Kubernetes clusters and supporting resources on **AWS** and **GCP** using Terragrunt/Terraform.

## Repository Structure

```
compute-ansible-machines/
├── aws/                              # AWS infrastructure
│   ├── root.hcl                      # Terragrunt root (S3 backend, AWS provider)
│   ├── terraform/modules/            # Terraform modules
│   │   ├── vpc/                      # VPC + subnets + NAT Gateway
│   │   ├── eks/                      # EKS cluster + node groups + IAM roles
│   │   ├── general/                  # Post-EKS: LBC, ASCP (Secrets CSI)
│   │   ├── identity/                 # Pod Identity associations
│   │   ├── roles/                    # Admin + CI/CD roles (prod)
│   │   └── oidc/                     # GitHub OIDC provider + CI/CD role
│   └── us-east-1/compute-ansible/
│       ├── shared/oidc/              # Account-level OIDC (admin-only)
│       ├── dev/blue/{vpc,eks,general}/    # Dev environment (blue cluster)
│       └── prod/{vpc,roles,eks,general}/ # Prod environment
│
├── gcp/                              # GCP infrastructure
│   ├── root.hcl                      # Terragrunt root (GCS backend, Google provider)
│   ├── terraform/modules/            # Terraform modules
│   │   ├── vpc/                      # VPC + subnet + Cloud Router + Cloud NAT
│   │   ├── gke/                      # GKE private cluster + node pools
│   │   ├── general/                  # Post-GKE: Secrets Store CSI Driver
│   │   └── wif/                      # Workload Identity Federation for CI/CD
│   └── us-central1/compute-ansible/
│       ├── shared/wif/               # Account-level WIF (admin-only)
│       └── dev/{vpc,gke,general}/    # Dev environment
│
├── .github/workflows/                # CI/CD pipelines
│   ├── aws-kubernetes-{plan,provision,destroy}.yaml
│   └── gcp-kubernetes-{plan,provision,destroy}.yaml
│
└── bin/                              # Helper scripts (connect, etc.)
```

## Architecture Principles

The infrastructure follows a **directory-as-contract** pattern where the directory path encodes deployment topology:

```
<provider>/<region>/<application>/<environment>/<color>/<component>
```

- `root.hcl` derives `environment`, `region`, and provider config from the path
- Each environment has its own remote state backend (no cross-environment sharing)
- `shared/` contains account-level resources applied manually by administrators
- `dev/`, `prod/` are deployed via GitHub Actions using `terragrunt apply --all --non-interactive`
- Color-based versioning allows blue/green cluster rotation within an environment

---

## AWS Infrastructure

**Region**: `us-east-1` | **Profile**: `devops-compute-ansible` | **Account**: `317374277503`

### Components

| Component | Module | Why |
|-----------|--------|-----|
| **VPC** | `aws/terraform/modules/vpc/` | Isolated network with private/public subnets across 3 AZs (us-east-1a, us-east-1b, us-east-1c), secondary CIDR (`100.64.0.0/16`) for pod IPs, NAT Gateway for outbound traffic, VPC endpoints for S3/MQ |
| **EKS** | `aws/terraform/modules/eks/` | Managed Kubernetes cluster with managed node groups, admin/developer IAM roles with EKS access entries, CI/CD role integration |
| **General** | `aws/terraform/modules/general/` | Post-cluster orchestrator: AWS Load Balancer Controller (Helm) for Ingress/Gateway API, ASCP (Secrets Store CSI Driver) for mounting AWS Secrets Manager secrets as files |
| **Identity** | `aws/terraform/modules/identity/` | Pod Identity associations for service accounts (e.g., LBC needs IAM permissions) |
| **OIDC** | `aws/terraform/modules/oidc/` | GitHub OIDC provider + CI/CD IAM role (`next-signal-github-actions`) so GitHub Actions can authenticate without long-lived credentials |
| **Roles** | `aws/terraform/modules/roles/` | Admin + CI/CD roles for prod (separate lifecycle from EKS) |

### State Backend

S3 buckets with native locking (Terraform 1.10+):
- `compute-ansible-tg-state-shared`
- `compute-ansible-tg-state-dev`
- `compute-ansible-tg-state-prod`

### Deployment

```bash
# 1. Account-level (admin, once)
cd aws/us-east-1/compute-ansible/shared/oidc && terragrunt apply

# 2. Per environment using just recipes
just aws-plan dev blue
just aws-apply dev blue

# Or target a single component
cd aws/us-east-1/compute-ansible/dev/blue/vpc && terragrunt apply
```

### Cluster Access

```bash
# Using the connect script (takes color arg)
./bin/aws-connect.sh dev blue admin       # Connect as admin
./bin/aws-connect.sh dev blue developer   # Connect as developer

# Or manually
aws eks update-kubeconfig --name compute-ansible-dev-blue \
  --role-arn arn:aws:iam::317374277503:role/compute-ansible-dev-blue-admin \
  --profile devops-compute-ansible
```

### Network

- **VPC CIDR (blue)**: `10.0.0.0/16`
- **Availability Zones**: `us-east-1a`, `us-east-1b`, `us-east-1c`
- **Pod CIDR (secondary)**: `100.64.0.0/16`

### CI/CD Workflows

| Workflow | Command | Auth |
|----------|---------|------|
| `aws-kubernetes-plan.yaml` | `init --all` + `plan --all` | GitHub OIDC -> IAM Role (`next-signal-github-actions`) |
| `aws-kubernetes-provision.yaml` | `init --all` + `apply --all` | GitHub OIDC -> IAM Role (`next-signal-github-actions`) |
| `aws-kubernetes-destroy.yaml` | `init --all` + `destroy --all` | GitHub OIDC -> IAM Role (`next-signal-github-actions`) |

---

## GCP Infrastructure

**Region**: `us-central1` | **Project**: `TBD`

### Components

| Component | Module | Why |
|-----------|--------|-----|
| **VPC** | `gcp/terraform/modules/vpc/` | Google VPC network with private subnet, secondary IP ranges for GKE pods and services, Cloud Router + Cloud NAT for outbound traffic from private nodes |
| **GKE** | `gcp/terraform/modules/gke/` | GKE private cluster with Workload Identity, Gateway API, and DNS caching built-in. Two node pools: general (on-demand) and compute (spot with taints). No separate LBC needed (GKE handles load balancing natively) |
| **General** | `gcp/terraform/modules/general/` | Post-cluster: Secrets Store CSI Driver (Helm) + GCP Secret Manager provider (K8s manifests -- no official Helm chart exists) for mounting GCP Secret Manager secrets as files in pods |
| **WIF** | `gcp/terraform/modules/wif/` | Workload Identity Federation pool + OIDC provider + CI/CD service account so GitHub Actions can authenticate with GCP without long-lived credentials |

### GCP vs AWS Simplifications

| AWS Component | GCP Equivalent | Notes |
|---------------|----------------|-------|
| VPC + secondary CIDR | VPC + secondary IP ranges | GKE uses named secondary ranges instead of secondary CIDRs |
| EKS + addons (vpc-cni, coredns, etc.) | GKE (all built-in) | GKE bundles CNI, DNS, metrics - no addon management needed |
| AWS Load Balancer Controller | Built-in (`http_load_balancing`) | GKE natively integrates with Cloud Load Balancing |
| Pod Identity module | Workload Identity (built-in) | Configured at cluster level, no separate module |
| ASCP (bundled CSI driver) | CSI driver (Helm) + GCP provider (K8s manifests) | GCP has no official Helm chart for the provider |
| GitHub OIDC provider | WIF pool + OIDC provider | GCP uses Workload Identity Federation |
| IAM roles + assume-role chains | IAM bindings (direct) | Simpler model, bindings in GKE module |

### State Backend

GCS buckets with built-in locking (auto-created by Terragrunt):
- `compute-ansible-tg-state-gcp-shared`
- `compute-ansible-tg-state-gcp-dev`
- `compute-ansible-tg-state-gcp-prod`

### Deployment

```bash
# 1. Account-level (admin, once)
cd gcp/us-central1/compute-ansible/shared/wif && terragrunt apply

# 2. Per environment using just recipes
just gcp-plan dev
just gcp-apply dev

# Or target a single component
cd gcp/us-central1/compute-ansible/dev/vpc && terragrunt apply
```

### Cluster Access

```bash
# Using the connect script
./bin/gcp-connect.sh dev              # Connect to dev cluster
./bin/gcp-connect.sh dev us-central1  # Explicit region

# Or manually
gcloud container clusters get-credentials compute-ansible-dev-blue \
  --region us-central1 \
  --project TBD

kubectl get nodes
```

### CI/CD Workflows

| Workflow | Command | Auth |
|----------|---------|------|
| `gcp-kubernetes-plan.yaml` | `init --all` + `plan --all` | WIF -> Service Account |
| `gcp-kubernetes-provision.yaml` | `init --all` + `apply --all` | WIF -> Service Account |
| `gcp-kubernetes-destroy.yaml` | `init --all` + `destroy --all` | WIF -> Service Account |

**GitHub Secrets Required**:
- `GCP_WIF_PROVIDER_DEV` / `GCP_WIF_PROVIDER_PROD` - WIF provider name (from `shared/wif` output)
- `GCP_SERVICE_ACCOUNT_DEV` / `GCP_SERVICE_ACCOUNT_PROD` - CI/CD service account email (from `shared/wif` output)

> `PROJECT_ID` is hardcoded in the workflow files -- not a secret.

---

## Node Pools

Both clouds use the same two-pool strategy:

| Pool | AWS (EKS) | GCP (GKE) | Why |
|------|-----------|-----------|-----|
| **Core** (`compute-ansible-core`) | `t3a.medium`, ON_DEMAND, 1-3 nodes | `e2-medium`, on-demand, 1-3 nodes | System workloads (controllers, monitoring). Always-on for cluster stability |
| **Compute** (`compute-ansible-compute`) | `c5a.xlarge`, SPOT, 0-4 nodes | `c2-standard-4`, spot, 0-4 nodes | AI/compute workloads. Scale-to-zero when idle. Spot instances for cost optimization |

---

## FinOps Tags

All resources are tagged with the following for cost attribution and governance:

| Tag | Example Value | Purpose |
|-----|---------------|---------|
| `Project` | `compute-ansible` | Top-level project identifier |
| `Environment` | `dev` | Deployment environment |
| `ClusterColor` | `blue` | Blue/green cluster rotation identifier |
| `ManagedBy` | `terragrunt` | IaC tool managing the resource |
| `Repo` | `next-signal/compute-ansible-machines` | Source repository |

---

## Dependencies & Deploy Order

Both AWS and GCP follow the same dependency pattern:

```
shared (admin-only, once)
└── Environment (CI/CD)
    ├── VPC/Network
    │   └── EKS/GKE (cluster)
    │       └── General (post-cluster Helm releases)
    └── (independent of each other within env)
```

Terragrunt `dependency` blocks enforce this ordering automatically when running `--all`.

## Tooling Requirements

| Tool | Version |
|------|---------|
| Terraform | >= 1.12.x |
| Terragrunt | >= 0.81.x |
| just | >= 1.x |
| AWS CLI | >= 2.x (for AWS) |
| gcloud CLI | latest (for GCP) |

## Gotchas

1. **`terraform_wrapper: false`** - Always set this in `hashicorp/setup-terraform` GitHub Actions steps. The wrapper corrupts JSON output that Terragrunt needs for dependency resolution.
2. **`run-all` is deprecated** - Use `terragrunt <command> --all --non-interactive` instead of `terragrunt run-all <command>`.
3. **GCS bucket names are globally unique** - The `compute-ansible-tg-state-gcp-{env}` naming convention includes the provider prefix to avoid collisions with AWS buckets.
4. **ASCP v2.x bundles the CSI driver** (AWS only) - Do NOT install `secrets-store-csi-driver` separately alongside ASCP. On GCP, they are two separate charts.
5. **`base64decode()` on sensitive values** - Wrap with `nonsensitive()` before decoding: `base64decode(nonsensitive(var.ca_cert))`. The CA certificate is public data.
6. **Account ID from `region.hcl`** (AWS) - Never use `get_aws_account_id()` which runs before provider configuration.
