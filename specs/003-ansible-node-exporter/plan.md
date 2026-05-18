# Implementation Plan: Ansible Node Exporter on SSM-Managed EC2

**Branch**: `003-ansible-node-exporter` · **Date**: 2026-05-17 · **Spec**: [./spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-ansible-node-exporter/spec.md`

## Summary

Introduce the **first Ansible layer** to this repo. It converges *software state* — specifically Prometheus Node Exporter v1.10.2 — onto the existing EC2 fleet provisioned by Terragrunt under `aws/dev/<region>/bluemesh/ec2/`, reachable only via AWS SSM Session Manager. A new GitHub Actions workflow runs Ansible on push to `main`, on manual dispatch, and on an hourly schedule for drift reconciliation. Authentication uses the repo's existing GitHub OIDC pattern. Workflow exit code is trigger-aware: strict for push/dispatch, threshold-based (>20% failed) for the hourly schedule.

Two precondition gaps surfaced during research and will land as a separate sub-topic branch *before* the Ansible work can run end-to-end: (1) added SSM/EC2/S3 permissions on the existing OIDC role, and (2) a small S3 staging bucket required by the `amazon.aws.aws_ssm` connection plugin.

## Technical Context

**Language/Version**: Ansible 2.17.x (control side, on GitHub Actions); shell-installable Linux on hosts (Amazon Linux 2023 + Ubuntu LTS supported by AMI choice in `ec2-extended`)
**Primary Dependencies**: `amazon.aws==10.*` collection, `boto3>=1.34`, `botocore>=1.34`, AWS Session Manager Plugin
**Storage**: One small S3 bucket per (env, region) for SSM file transfer (new, provisioned by Terragrunt). No persisted application data.
**Testing**: `ansible-lint`, `ansible-playbook --syntax-check`, `ansible-playbook --check --diff` (dry run), plus a runtime `uri:` verification of `/metrics` per host. No host-level unit tests (the role is the test surface).
**Target Platform**: EC2 Linux instances (`x86_64` and `aarch64`) under `aws/<account>/<region>/<versionmesh>/ec2/`
**Project Type**: Infrastructure / configuration-management; CI-driven, declarative
**Performance Goals**: SC-001 ≤5 min single host fresh install; SC-005 ≤10 min for 25 hosts; SC-002 zero-changed re-run
**Constraints**: No SSH; no port 22; no static AWS keys; no host-level firewall changes; no kube* naming; no eBPF in this slice (FR-015)
**Scale/Scope**: 1–25 EC2 instances in `dev` `us-east-1` `bluemesh` for v1; designed to scale further by tag selector only

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
| --- | --- | --- |
| **I. Infrastructure as Code** | ✅ Pass | The new S3 staging bucket and OIDC policy additions are HCL under Terraform/Terragrunt. The Ansible layer is itself code under `ansible/`. Standard repo tags (Project / Account / Region / Versionmesh / ManagedBy / Repo) are reused; the EC2-level `deployment_code` tag is preserved (not modified). |
| **II. Git-Driven Deployment (NON-NEGOTIABLE)** | ✅ Pass | All applies flow through GitHub Actions with OIDC. Local `just ansible-apply` is documented as emergency-only (mirrors how `just aws-apply` is treated). No long-lived AWS credentials introduced (FR-007). Sub-topic-branch convention preserved. |
| **III. Directory-as-Contract** | ✅ Pass | Ansible lives at top-level `ansible/` (separate from `aws/`, `gcp/`, `azure/`). New shared resource `aws/dev/shared/ansible-ssm-bucket/` follows the `<provider>/<account>/shared/<component>` pattern. No path-level config is hardcoded inside `terragrunt.hcl`. |
| **IV. Spec-Driven Development** | ✅ Pass | Feature branch `003-ansible-node-exporter` exists. Spec → clarify → plan → tasks → implement is the active flow. Acceptance scenarios map to dry-run output (`ansible-playbook --check --diff`) and to `systemctl is-active`. |
| **V. Automation via Just** | ✅ Pass | All Ansible operations are wrapped as `just ansible-setup / ansible-inventory / ansible-check / ansible-plan / ansible-apply` recipes (research Decision 8). CI invokes the recipes, not raw `ansible-playbook`. |

**Deployment & CI/CD constraints**:

- Zero static credentials ✅ (OIDC reuse)
- Trust boundary respected: workflow trigger restricted to `main` + `test/*`, same as existing workflows
- Admin-only resource handling: the OIDC role *modification* is itself admin-only (under `aws/dev/shared/oidc/`); the Ansible workflow CANNOT modify its own trust policy
- State isolation: each env still has its own state backend; the new bucket is per env
- `terraform_wrapper: false`: N/A here (no Terraform run inside the Ansible workflow)

**No gate violations.** No `Complexity Tracking` entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/003-ansible-node-exporter/
├── plan.md                         # this file
├── spec.md                         # written by /speckit-specify, updated by /speckit-clarify
├── research.md                     # Phase 0 output — decisions + repo-state findings
├── data-model.md                   # Phase 1 output — workflow inputs, inventory, role vars
├── quickstart.md                   # Phase 1 output — operator-facing 5-minute path
├── contracts/
│   ├── workflow-inputs.schema.yaml # Phase 1 — GH Actions inputs as JSON Schema
│   └── role-interface.md           # Phase 1 — role API surface + guarantees
├── checklists/
│   └── requirements.md             # from /speckit-specify
└── tasks.md                        # produced by /speckit-tasks (next phase)
```

### Source Code (repository root)

```text
ansible/                                          # NEW — top-level Ansible layer
├── ansible.cfg                                   # pinned defaults, inventory plugin enable
├── requirements.txt                              # ansible-core==2.17.*, boto3, botocore
├── requirements.yml                              # amazon.aws==10.*, community.general==9.*
├── inventories/
│   └── aws/
│       └── dynamic.aws_ec2.yml                   # amazon.aws.aws_ec2 plugin config
├── playbooks/
│   └── install-node-exporter.yml                 # single entry point for v1
├── roles/
│   └── node_exporter/
│       ├── defaults/main.yml
│       ├── handlers/main.yml
│       ├── tasks/
│       │   ├── main.yml
│       │   ├── preflight.yml
│       │   ├── user.yml
│       │   ├── install.yml
│       │   ├── service.yml
│       │   └── verify.yml
│       ├── templates/
│       │   └── node_exporter.service.j2
│       └── README.md
├── scripts/
│   └── exit-code.sh                              # parses ansible JSON callback; trigger-aware (FR-017)
└── README.md                                     # operator-facing layer doc

.github/workflows/
└── ansible-node-exporter.yaml                    # NEW — push/dispatch/schedule triggers, OIDC, concurrency

justfile                                          # APPEND — `ansible-*` recipes

aws/dev/shared/oidc/                              # MODIFIED (admin-only apply)
└── ...                                           # adds SSM / EC2-describe / S3 permissions to OIDC role

aws/dev/<region>/ansible-ssm-bucket/              # NEW (per-region, not under shared)
└── terragrunt.hcl                                # 1 S3 bucket + bucket policy granting EC2 role read
aws/terraform/modules/ansible-ssm-bucket/         # NEW module
├── main.tf
├── variables.tf
├── outputs.tf
└── versions.tf
```

**Structure Decision**:

- Top-level `ansible/` (sibling of `aws/`, `gcp/`, `azure/`). Matches constitutional Principle III (each provider/concern at the top level, no nesting under another).
- `aws/dev/shared/oidc/` is **modified**, not duplicated. The IAM additions live in the existing OIDC module as new inline policy attachments.
- The S3 bucket lives at `aws/dev/<region>/ansible-ssm-bucket/` (per-account, per-region), not under `shared/`, because its lifecycle is *not* admin-only — it can be managed by CI/CD like other env resources. Admin-only is reserved for OIDC/WIF/trust policies per the constitution.
- No `tests/` directory is created. Ansible's intrinsic check mode + verify tasks + the workflow exit-code helper are the test surface for v1.

## Phase 0: Outline & Research

See [./research.md](./research.md). All NEEDS-CLARIFICATION items resolved.

Top-level decisions:

1. **Tag selector** — repo-state finding: the spec's clarified tags (`Environment=dev`, `Process=monitoring`, `version=blue`, `Owner=<repo>`) **do not exist** on the live EC2 fleet today. v1 uses an adapter selector that maps to the actual tags (`Project=compute-ansible`, `Account=dev`, `Versionmesh=bluemesh`, `Service=ec2-extended`, `instance-state-name=running`). The spec's clarified selector becomes accurate after a follow-up sub-topic branch that adds the new tags to the `ec2-extended` module.
2. **IAM gaps** — OIDC role and EC2 instance profile both need additions; addressed in a precondition sub-topic branch before the Ansible workflow can run.
3. **S3 staging bucket** — `amazon.aws.aws_ssm` requires it (even for shell modules); provisioned by Terragrunt as a new component.
4. **Ansible versions** — `ansible-core==2.17.*` + `amazon.aws==10.*`.
5. **Connection plugin** — `amazon.aws.aws_ssm` configured via inventory `compose:`; `hostnames: instance-id` is mandatory.
6. **Node Exporter source** — direct from GitHub releases, verified against `sha256sums.txt` (FR-012).
7. **Role split** — 5 task files for readability + iteration speed.
8. **Workflow exit code** — bash helper script parses Ansible JSON callback; logic differs by `GITHUB_EVENT_NAME` per FR-017.
9. **`just` recipes** — 5 new recipes: `ansible-setup`, `ansible-inventory`, `ansible-check`, `ansible-plan`, `ansible-apply` (Principle V).
10. **Out-of-scope confirmed** — no eBPF, no Packer/AMI, no TLS, no Prometheus instance, no prod env.

## Phase 1: Design & Contracts

See [./data-model.md](./data-model.md) and [./contracts/](./contracts/).

Key design outputs:

- **Workflow inputs schema** (JSON Schema in `contracts/workflow-inputs.schema.yaml`): typed, defaults, validation rules (`prod` rejected; `failure_threshold_pct` coerced to 100 on push/dispatch).
- **Dynamic inventory** uses `amazon.aws.aws_ec2` with the adapter tag set + `compose:` to set `ansible_connection=aws_ssm`. Hostnames are instance IDs (mandatory for SSM).
- **Role interface** (`contracts/role-interface.md`) lists every overridable variable, the guarantees on successful completion, the idempotency contract, and the host-level failure modes.
- **Quickstart** ([./quickstart.md](./quickstart.md)) — 5-minute operator path from clone to "Node Exporter running on bluemesh". Also lists 9 manual acceptance tests mapping to spec scenarios.

### Re-evaluated Constitution Check (post-design)

| Principle | Re-check |
| --- | --- |
| I. IaC | Still pass — bucket + IAM additions are HCL; Ansible is code. |
| II. Git-Driven Deployment | Still pass — CI is the apply path; emergency local apply documented as exception. |
| III. Directory-as-Contract | Still pass — `ansible/` at top level, new `aws/dev/<region>/ansible-ssm-bucket/` matches existing patterns. |
| IV. Spec-Driven Development | Still pass — design artifacts complete; tasks next. |
| V. Automation via Just | Still pass — 5 recipes specified; CI invokes them. |

No new violations introduced by Phase 1 design.

## Implementation phasing (preview — to be expanded by `/speckit-tasks`)

`/tasks` will produce `tasks.md`. The expected phasing is:

1. **Phase A (Preconditions, sub-topic branch `003-...--iam-and-bucket`)**: New S3 bucket module + Terragrunt config + OIDC policy additions. Apply locally (admin-only per Principle II for shared OIDC).
2. **Phase B (Ansible layer, this branch)**: `ansible/` tree + `roles/node_exporter` + playbook + inventory + `requirements`.
3. **Phase C (Automation)**: `justfile` recipes + GitHub Actions workflow + `exit-code.sh` helper.
4. **Phase D (Validation)**: dry-run via `just ansible-plan`, then a real `workflow_dispatch` run on `bluemesh` dev, then verify against acceptance tests in `quickstart.md`.

## Open issues / known follow-ups

- **Tag-schema alignment** (sub-topic `003-...--align-tag-schema`): add `Environment`, `Process`, `Owner` (and rename `Versionmesh→version` if desired) to the `ec2-extended` module so the spec's clarified selector becomes the live selector. Not blocking v1.
- **Prod promotion** (`004-ansible-node-exporter-prod` or similar): expand the workflow's `account` enum acceptance to include `prod`, validate the prod OIDC role has equivalent permissions.
- **eBPF agent** (`004-rust-ebpf-agent`): once Node Exporter is in steady state, add a second role + a second play to the same playbook. The Ansible layer is structured for that addition.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

None. All five constitutional principles pass at both gates.
