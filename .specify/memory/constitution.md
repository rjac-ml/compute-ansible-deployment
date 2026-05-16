<!--
  Sync Impact Report
  ==================
  Version change: 0.0.0 → 1.0.0 (MAJOR — initial ratification)
  
  Modified principles: N/A (first version)
  
  Added sections:
    - Principle I: Infrastructure as Code
    - Principle II: Git-Driven Deployment
    - Principle III: Directory-as-Contract
    - Principle IV: Spec-Driven Development
    - Principle V: Automation via Just
    - Section: Deployment & CI/CD Constraints
    - Section: Development Workflow
    - Section: Governance
  
  Removed sections: N/A
  
  Templates requiring updates:
    - .specify/templates/plan-template.md — ⚠️ pending
      (Technical Context defaults assume app code; IaC plans should
       use HCL/Terragrunt context instead. Adapt per-spec, not globally.)
    - .specify/templates/spec-template.md — ✅ compatible
      (User stories and acceptance scenarios work for IaC features.)
    - .specify/templates/tasks-template.md — ⚠️ pending
      (Path conventions reference src/tests/; IaC specs should use
       aws/gcp module paths. Adapt per-spec, not globally.)
  
  Follow-up TODOs: None
-->

# Compute-Ansible Machines Constitution

## Core Principles

### I. Infrastructure as Code

All infrastructure MUST be defined declaratively in version-controlled
HCL (Terraform modules + Terragrunt configurations). No manual
cloud-console changes are permitted outside of emergency break-glass
scenarios, and any such changes MUST be imported into Terraform state
and codified immediately after.

- Terraform modules live under `<provider>/terraform/modules/`.
- Terragrunt configurations live under
  `<provider>/<account>/<region>/<versionmesh>/<component>/`.
- Every cloud resource MUST be tagged/labeled for cost attribution
  (Project, Environment, Versionmesh, ManagedBy, Repo).
- EC2 deployments MUST include a `deployment_code` tag for
  tag-based service discovery.

### II. Git-Driven Deployment (NON-NEGOTIABLE)

Deployments MUST flow through Pull Requests and GitHub Actions. No
local `terragrunt apply` except for `shared/` admin-only resources
(OIDC, WIF) which require elevated credentials by design.

- Feature work happens on branches; merging to `main` (or `test/*`)
  triggers CI/CD via GitHub Actions workflow dispatch.
- Local execution is limited to `terragrunt plan` (read-only) and
  one-time bootstrap scripts.
- All apply/destroy operations in dev and prod environments MUST
  execute through GitHub Actions using OIDC/WIF authentication with
  zero long-lived credentials.

### III. Directory-as-Contract

The directory path encodes the full deployment topology and MUST
follow the pattern:

```
<provider>/<account>/<region>/<versionmesh>/<component>
```

Account-level shared resources follow:

```
<provider>/<account>/shared/<component>
```

- `root.hcl` in each provider directory derives environment, region,
  state backend, and provider config from the path automatically.
- Account, region, and provider settings MUST NOT be hardcoded in
  individual `terragrunt.hcl` files.
- Account config lives in `account.hcl`, region config in `region.hcl`.
- Adding a new account or region requires only creating the
  directory structure with config files — no changes to root config.

### IV. Spec-Driven Development

Because all infrastructure is versioned code, the Spec-Driven
Development workflow applies to infrastructure changes:

- Non-trivial changes (new modules, new environments, new provider
  integrations, security model changes) MUST go through the
  Specify → Plan → Tasks → Implement cycle.
- Each spec produces a feature branch, implementation plan, and
  task list before any HCL is written.
- Specs MUST include acceptance scenarios that map to `terragrunt plan`
  output validation (expected resource counts, no destructive changes
  unless intended).

### V. Automation via Just

All repeatable operations MUST be codified as `just` recipes in the
project `justfile`. Direct `terragrunt` or `terraform` CLI invocations
SHOULD only be used for debugging or one-off exploration.

- CI/CD workflows MUST use `just` recipes for plan/apply/destroy.
- New operational patterns (e.g., connecting to clusters, syncing
  secrets) MUST be added as `just` recipes before being documented
  as manual steps.
- `just fmt` and `just validate` MUST pass before merging.

## Deployment & CI/CD Constraints

- **Zero static credentials**: AWS uses GitHub OIDC -> IAM role
  assumption; GCP uses GitHub OIDC -> WIF -> SA impersonation.
  No access keys or SA JSON keys exist anywhere.
- **Trust boundaries**: AWS OIDC trust is scoped to `main` and
  `test/*` branches of `next-signal/compute-ansible-*` repos.
  GCP WIF pool enforces org ownership + repo prefix at the
  `attribute_condition` level.
- **Admin-only resources**: `shared/` components (OIDC, WIF) MUST
  be applied locally by an admin. CI/CD MUST NOT be able to modify
  its own trust policy or permissions.
- **State isolation**: Each environment has its own state backend.
  Dev workflows MUST NOT be able to read or write prod state.
- **`terraform_wrapper: false`**: MUST be set in all CI/CD
  `setup-terraform` steps — the wrapper corrupts JSON output that
  Terragrunt depends on.

## Development Workflow

1. **Spec**: Define the change via `/speckit-specify` with acceptance
   criteria that can be validated against `terragrunt plan` output.
2. **Branch**: Create a feature branch following the `###-feature-name`
   convention.
3. **Implement**: Write HCL modules and Terragrunt configs. Run
   `just fmt` and `just validate` locally.
4. **Plan**: Run `just <provider>-plan <account> <region> <versionmesh>` locally to
   verify expected changes (read-only).
5. **PR**: Open a Pull Request. CI runs `terragrunt plan --all` via
   GitHub Actions and posts the plan output.
6. **Merge**: After review and approval, merge triggers the provision
   workflow which runs `terragrunt apply --all`.
7. **Verify**: Confirm deployment via cluster access scripts
   (`bin/aws-connect.sh`, `bin/gcp-connect.sh`).

## Governance

- This constitution supersedes ad-hoc practices. All PRs and reviews
  MUST verify compliance with these principles.
- Amendments require: (1) a PR modifying this file, (2) review and
  approval, (3) version bump following semver (MAJOR for principle
  removal/redefinition, MINOR for additions, PATCH for clarifications).
- Refer to `CLAUDE.md` for runtime development guidance and HCL
  conventions.

**Version**: 1.1.0 | **Ratified**: 2026-05-11 | **Last Amended**: 2026-05-11
