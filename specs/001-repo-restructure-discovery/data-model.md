# Data Model: Repository Restructure & VM Service Discovery

**Date**: 2026-05-11

## Entities

### Account

Represents an AWS account boundary. Determines credentials, state backend, and OIDC trust scope.

| Field | Type | Source | Example |
|-------|------|--------|---------|
| account | string | directory path (`path_parts[0]`) | `dev` |
| account_id | string | `account.hcl` | `317374277503` |
| profile | string | `account.hcl` | `devops-compute-ansible` |

**Constraints**: Must be one of: `dev`, `stage`, `prod`, or a custom name (e.g., `cust1`). Maps 1:1 to an AWS account ID.

### Region

AWS region within an account.

| Field | Type | Source | Example |
|-------|------|--------|---------|
| region | string | directory path (`path_parts[1]`) + `region.hcl` | `us-east-1` |

### Versionmesh

A named deployment version within an account and region. Independent infrastructure stack.

| Field | Type | Source | Example |
|-------|------|--------|---------|
| versionmesh | string | directory path (`path_parts[2]`) | `bluemesh` |

**Naming convention**: `<version>mesh` (bluemesh, redmesh, greenmesh, etc.)

**Constraints**: Must end with `mesh`. Each versionmesh within an account+region has isolated state.

### Deployment Code

Composite identifier for tag-based service discovery.

| Field | Type | Composition | Example |
|-------|------|-------------|---------|
| deployment_code | string | `<versionmesh>-<account>-<region>` | `bluemesh-dev-us-east-1` |

**Constraints**: Globally unique within an AWS account. Applied as an EC2 tag to all instances in a deployment.

## Relationships

```
Account (1) ──── has many ───→ Region (N)
Region  (1) ──── has many ───→ Versionmesh (N)
Versionmesh (1) ── generates ─→ Deployment Code (1)
Versionmesh (1) ── contains ──→ Components (N: vpc, ec2, etc.)
Account (1) ──── has one ────→ Shared (oidc)
```

## Directory-to-Entity Mapping

```
aws/               ← provider (implicit)
├── dev/            ← Account { account: "dev", account_id: "317374277503" }
│   ├── account.hcl
│   ├── shared/     ← Account-scoped resources (no region, no versionmesh)
│   │   └── oidc/
│   └── us-east-1/  ← Region { region: "us-east-1" }
│       ├── region.hcl
│       └── bluemesh/ ← Versionmesh { versionmesh: "bluemesh" }
│           │           Deployment Code: "bluemesh-dev-us-east-1"
│           ├── vpc/
│           └── ec2/
```

## Tag Schema (EC2 Instances)

| Tag | Value | Purpose |
|-----|-------|---------|
| `Name` | `compute-ansible-dev-bluemesh-cp-1` | Instance identification |
| `Project` | `compute-ansible-dev` | Cost attribution |
| `Environment` | `dev` | Account/environment filter |
| `Versionmesh` | `bluemesh` | Replaces `ClusterColor` |
| `deployment_code` | `bluemesh-dev-us-east-1` | Peer discovery filter |
| `Role` | `control-plane` / `worker` | Role-based filtering |
| `DeployID` | git short SHA | Deploy versioning |
| `ManagedBy` | `Terragrunt` | IaC tool |
| `Repo` | `next-signal/compute-ansible-machines` | Source repo |

**Note**: `ClusterColor` tag is renamed to `Versionmesh` in `root.hcl` default_tags.
