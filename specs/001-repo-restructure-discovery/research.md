# Research: Repository Restructure & VM Service Discovery

**Date**: 2026-05-11
**Branch**: `001-repo-restructure-discovery`

## Decision 1: Directory Layout Pattern

**Decision**: `<provider>/<account>/<region>/<versionmesh>/<component>/`

**Rationale**: Account-first ordering matches how AWS organizes resources — account is the broadest trust boundary, region is within an account, and versionmesh is a deployment unit within a region. This makes the path readable left-to-right from broadest to narrowest scope. Removing the `compute-ansible` directory level eliminates redundancy (this is a single-application repo).

**Alternatives considered**:
- `<provider>/<region>/<account>/<versionmesh>` — rejected because account is a broader scope than region; querying "what's deployed in dev" requires scanning multiple region directories
- `<provider>/<account>/<versionmesh>/<region>` — rejected because a single versionmesh could theoretically span regions, but in practice each deployment is region-specific
- Keep `compute-ansible` directory level — rejected; it adds no information in a single-app repo and increases nesting depth

## Decision 2: Config File Split (account.hcl + region.hcl)

**Decision**: Introduce `account.hcl` at the account level (`aws/dev/account.hcl`) containing account_id and profile. Simplify `region.hcl` to contain only the region name.

**Rationale**: The current `region.hcl` conflates account-level config (account_id, profile) with region-level config (region name). With the new layout, account-level config is shared across all regions within an account, so it belongs one level up. This avoids duplicating account_id/profile in every region's `region.hcl`.

**Alternatives considered**:
- Keep everything in `region.hcl` — rejected; would duplicate account_id across `us-east-1/region.hcl`, `eu-west-1/region.hcl`, etc.
- Use a single `env.hcl` — rejected; separating account from region makes the hierarchy explicit

## Decision 3: Service Discovery Mechanism

**Decision**: EC2 tag queries (`ec2:DescribeInstances --filters`) combined with IMDS instance tags for self-identification.

**Rationale**: This is the pattern used by Consul (auto-join), Elasticsearch (EC2 discovery plugin), and Teleport (EC2 auto-discovery). Zero cost, no additional AWS services, and works with spot instance replacements automatically. IMDS tags fix a latent bug where `user-data.sh` calls `describe-tags` without IAM permissions.

**Alternatives considered**:
- AWS Cloud Map — rejected; overkill for a 4-node lab cluster, adds service complexity and cost ($0.10/resource/month + API calls)
- SSM Parameter Store as registry — rejected; requires write permissions, has stale data problems (no auto-deregistration on terminate), and is hand-rolling a discovery service
- Route 53 only — already exists but is static (created at `terraform apply` time); tag-based discovery is dynamic and works even when instance IPs change (spot replacements)

## Decision 4: deployment_code Tag Format

**Decision**: `<versionmesh>-<account>-<region>` (e.g., `bluemesh-dev-us-east-1`)

**Rationale**: Including account and region ensures uniqueness across accounts. A `bluemesh` in dev and a `bluemesh` in stage will have different deployment_code values. The versionmesh name comes first for readability when filtering.

**Alternatives considered**:
- `<account>-<region>-<versionmesh>` — rejected; less readable, versionmesh is the primary differentiator within an account/region
- Use existing `DeployID` tag (git SHA) — rejected; changes on every deploy, not suitable for stable group identification
- Separate tags (filter by `versionmesh` + `account` + `region`) — viable but a composite `deployment_code` is simpler for a single `--filters` query

## Decision 5: Shared Resources Location

**Decision**: `aws/<account>/shared/<component>/` (e.g., `aws/dev/shared/oidc/`)

**Rationale**: Shared resources are account-scoped (OIDC provider is per-account). Placing them under the account directory makes the scope explicit. The `root.hcl` detects `shared` at `path_parts[1]` and skips region/versionmesh parsing.

**Alternatives considered**:
- `aws/shared/<account>/` — rejected; breaks the account-first pattern
- Keep at `aws/<region>/compute-ansible/shared/` — rejected; that's the old layout being replaced

## Decision 6: IAM Permission Scope

**Decision**: `ec2:DescribeInstances` + `ec2:DescribeTags` with `Resource = "*"` as an inline policy on the SSM role.

**Rationale**: These are read-only Describe actions that do not support resource-level permissions in IAM — `Resource = "*"` is the only valid value. The actions let instances list metadata about other EC2 instances in the account but grant no ability to modify, start, stop, or terminate anything. This is standard practice (AWS documentation confirms it).

**Alternatives considered**:
- Condition key `ec2:ResourceTag/deployment_code` — not supported for Describe actions; filtering happens at the API level, not IAM
- Separate IAM role for discovery — rejected; unnecessary role proliferation for two read-only actions
