# Spec Learnings

A running log of lessons learned from Spec-Driven Development cycles in this repo.
Each entry is a focused retrospective from one spec. New entries are appended at the bottom.

When starting a new spec, scan this file for relevant past learnings (match on tags, area, or topic) and surface the most relevant 3–5 entries before drafting.

Entry format:

## YYYY-MM-DD — Spec: <name>
**Outcome:** shipped | partial | abandoned
**Tags:** #tag1 #tag2

### What worked
### What didn't
### Technical patterns discovered
### Agent / prompt notes
### Action items for next specs

---

<!-- Entries below, newest at the bottom -->

## 2026-05-12 — Spec: 001-repo-restructure-discovery

**Outcome:** shipped
**Tags:** #iac #directory-restructure #ec2 #service-discovery #aws #az-compatibility

### What worked
- Incremental batched implementation (restructure → discovery → CI/CD → polish) with checkpoints gave clear validation points without being too slow
- Catching the greenfield vs state-migration question early avoided wasted planning — the research agent had already spent time on migration strategies but the correction came before any implementation work
- The SDD flow overall was solid for an IaC restructure — specs, plans, and tasks mapped well to Terraform/Terragrunt changes

### What didn't
- The spec inherited Kubernetes/kubeadm concepts from the existing module without questioning whether k8s was even in scope. The pivot to "plain EC2 instances with discovery" happened mid-implementation, requiring multiple passes to strip k8s references from the module, user-data, variables, tags, and docs. This should have been established in `/specify`.
- Instance type compatibility with AZs wasn't researched upfront. The path from t3a.micro → t3.micro → t2.micro required three deploy attempts and commits. us-east-1e is Xen-based (no Nitro) — a known AWS limitation that should have been caught in `/plan` research.

### Technical patterns discovered
- Pattern: **AZ instance compatibility check**. Before specifying instance types, verify availability across all target AZs. us-east-1e (use1-az3) only supports pre-Nitro instances (t2, m3, c3, etc.). Use `aws ec2 describe-instance-type-offerings --filters "Name=location,Values=<az>"` to verify.
- Pattern: **account.hcl + region.hcl split**. Separating account-level config (account_id, profile) from region-level config (region name) avoids duplication when an account spans multiple regions.
- Pattern: **OIDC provider as data source**. The GitHub OIDC provider is a per-account singleton. Use `data "aws_iam_openid_connect_provider"` instead of a resource to avoid conflicts across repos/stacks.
- Anti-pattern: **Hardcoding account IDs early**. Account IDs changed 3 times during development. Config values like account_id should be treated as mutable during initial setup — keep them in a single `account.hcl` file so changes propagate from one place.

### Agent / prompt notes
- Claude carried over k8s assumptions from the existing codebase without questioning relevance. For future specs: when repurposing an existing module, explicitly state in `/specify` what the module should and should NOT do.
- The SDD flow worked well overall — the research agents provided good coverage on directory patterns, discovery mechanisms, and state migration options.

### Action items for next specs
- [ ] In `/specify`: always ask "what is this deployment for?" before inheriting assumptions from existing modules
- [ ] In `/plan` research: when deploying EC2 across multiple AZs, include an AZ compatibility check for the chosen instance types
- [ ] In `/specify`: treat account IDs, profiles, and cloud config as variables that will change — don't bake them into the spec narrative
- [ ] When extending to GCP: apply the same account-first directory pattern (gcp/<project>/region/versionmesh/) from the start

## 2026-05-12 — Spec: 002-azure-infra-parity

**Outcome:** shipped
**Tags:** #azure #iac #vm-capacity #oidc #multi-cloud #discovery

### What worked
- Replicating the AWS pattern (root.hcl, account.hcl, region.hcl, versionmesh) transferred directly to Azure — the directory-as-contract principle is truly cloud-agnostic
- DNS auto-registration for peer discovery is simpler than tag-based API queries — fewer permissions, no IAM complexity, no `az` CLI install needed on VMs
- Sub-topic branch pattern (`002-azure-infra-parity--<topic>`) was excellent for iterating on fixes — each PR was small, focused, and independently reviewable. Keep this pattern.

### What didn't
- VM image name was wrong twice: first `0001-com-ubuntu-server-noble` (old naming convention), then wrong SKU. Azure image naming is not intuitive and must be verified with `az vm image list-offers` + `list-skus` before hardcoding
- Basv2 family had zero quota in East US (high demand). B1s had quota but only deployed in Zone 1 (zones 2/3 capacity constrained). Cost 4 deploy attempts and 3 PRs to resolve
- Contributor role cannot assign RBAC roles — the Reader role assignment for VM discovery failed. Had to remove it and simplify to DNS-based discovery
- Azure resource provider registration (`Microsoft.Storage`, `Microsoft.Compute`, etc.) is not automatic on new subscriptions — caused "SubscriptionNotFound" errors until registered
- Storage Account names are globally unique across all of Azure — first name choice (`smdeveastus`) was taken

### Technical patterns discovered
- Pattern: **Azure quota + SKU pre-check**. Before choosing a VM size, run `az vm list-usage --location <region>` (quota) AND `az vm list-skus --location <region> --size <size>` (zone availability). Start with 1 zone, validate, then expand.
- Pattern: **DNS auto-registration over API-based discovery**. Azure Private DNS Zone with `registration_enabled = true` auto-creates A records for VMs — zero IAM, zero API calls, zero extra tooling. Prefer this over tag-based discovery unless filtering by deployment_code is needed.
- Pattern: **Verify Azure image references via CLI**. Always run `az vm image list-offers --publisher Canonical --location <region>` + `az vm image list-skus` before hardcoding. Consider `azurerm_platform_image` data source for dynamic resolution.
- Pattern: **Simpler deployments = fewer permissions**. Contributor is sufficient when you avoid RBAC assignments in Terraform. If a feature requires User Access Administrator, reconsider whether the feature is worth the permission escalation.
- Pattern: **Sub-topic branches**. `<spec>--<topic>` naming (e.g., `002-azure-infra-parity--fix-image`) keeps fixes small, reviewable, and independently mergeable. Strongly preferred over accumulating changes on one branch.
- Anti-pattern: **Assuming Azure regions have uniform zone capacity**. East US zones 2/3 had no B1s capacity. This is transient but can block deployments for hours.

### Agent / prompt notes
- Claude used outdated Ubuntu image naming (research agent pulled wrong convention). For Azure-specific resources, always verify against the live subscription with `az` CLI rather than trusting web research
- The iterative sub-topic PR pattern kept each fix small and reviewable — Claude should default to this workflow

### Action items for next specs
- [ ] In `/plan`: always include an Azure quota + SKU availability check step before choosing VM sizes
- [ ] In `/specify`: for Azure deployments, state "start with 1 zone, expand after validation" as default
- [ ] In `/plan`: prefer solutions that work with Contributor role only — avoid requiring User Access Administrator
- [ ] Add `guide/azure/05-quota-and-sku-check.md` with the pre-deployment verification commands
- [ ] Consider using `azurerm_platform_image` data source instead of hardcoded image references
