# Data Model: Ansible Node Exporter

**Feature**: `003-ansible-node-exporter` · **Date**: 2026-05-17

Configuration-management features don't carry traditional persisted entities; the "data model" here is the set of inputs, defaults, and emitted facts that flow through the workflow → inventory → role → host. Each is testable as part of acceptance.

---

## Entity: Workflow Inputs (GitHub Actions `workflow_dispatch` schema + env)

| Field | Type | Required | Default | Constraints | Source |
| --- | --- | --- | --- | --- | --- |
| `account` | enum | yes | `dev` | one of `{dev, stage, prod}` | input |
| `region` | enum | yes | `us-east-1` | `us-east-1` only in v1 (matches SC-005 scope); future sub-topic may extend the enum | input |
| `versionmesh` | string | yes | `bluemesh` | matches an existing Terragrunt path `aws/<account>/<region>/<versionmesh>/ec2` | input |
| `node_exporter_version` | string | no | `1.10.2` | matches a published release tag at github.com/prometheus/node_exporter (no leading `v`) | input |
| `failure_threshold_pct` | integer | no | `20` | 0–100 inclusive; only consulted on `schedule` trigger | input |
| `extra_ansible_args` | string | no | `""` | passed verbatim to `ansible-playbook` for emergency overrides (e.g. `--limit i-abc123`) | input |
| `GH_ROLE_DEV` | string (ARN) | yes | (secret) | IAM role ARN trusted by GitHub OIDC | secret |
| `GH_ROLE_PROD` | string (ARN) | conditional | (secret) | required only for `account ∈ {stage, prod}` | secret |

**Validation rules**:

- The workflow MUST fail fast at job start if `account=prod` is selected (out of scope for v1).
- `node_exporter_version` MUST be validated by attempting to fetch `sha256sums.txt` from the corresponding release URL before any host work begins. A 404 fails the entire run immediately, before any SSM session is opened.
- `failure_threshold_pct` MUST be coerced to `100` when the trigger is `push` or `workflow_dispatch` (strict mode per FR-017).

---

## Entity: Dynamic Inventory (`amazon.aws.aws_ec2` plugin file)

File: `ansible/inventories/aws/dynamic.aws_ec2.yml`

| Field | Value | Notes |
| --- | --- | --- |
| `plugin` | `amazon.aws.aws_ec2` | canonical |
| `regions` | `["{{ lookup('env','ANSIBLE_AWS_REGION') }}"]` | one region per run |
| `filters.tag:Project` | `compute-ansible` | constitutional principle I |
| `filters.tag:Account` | `{{ lookup('env','ANSIBLE_AWS_ENV') }}` | dev / stage / prod |
| `filters.tag:Versionmesh` | `{{ lookup('env','ANSIBLE_AWS_VERSIONMESH') }}` | bluemesh (or future green) |
| `filters.tag:Service` | `ec2-extended` | the actual EC2 module name |
| `filters.instance-state-name` | `running` | excludes pending / stopped / shutting-down |
| `hostnames` | `[instance-id]` | required for SSM |
| `compose.ansible_connection` | `'aws_ssm'` | constant |
| `compose.ansible_aws_ssm_region` | the region literal | |
| `compose.ansible_aws_ssm_bucket_name` | `'compute-ansible-{{ ANSIBLE_AWS_ENV }}-{{ ANSIBLE_AWS_REGION }}-ansible-ssm'` | computed from env |
| `compose.ansible_aws_ssm_bucket_sse_mode` | `'AES256'` | |
| `compose.ansible_aws_ssm_s3_addressing_style` | `'virtual'` | per plugin docs |
| `compose.ansible_aws_ssm_timeout` | `120` | doubled from default 60 for slow apt/dnf hosts |
| `keyed_groups[0]` | key `tags.Versionmesh`, prefix `versionmesh` | yields group `versionmesh_bluemesh` for play targeting |
| `strict_permissions` | `false` | tolerate the workflow checking other regions for diagnostics |

**Note**: The selector here uses the *adapter set* documented in research Decision 1 (`Project`, `Account`, `Versionmesh`, `Service`), not the spec's clarified-but-not-yet-existing tag set (`Environment`, `Process`, `version`, `Owner`). The spec's selector becomes accurate after the (separate) tag-schema-alignment sub-topic branch.

---

## Entity: Role Defaults (`roles/node_exporter/defaults/main.yml`)

| Variable | Type | Default | Constraints |
| --- | --- | --- | --- |
| `node_exporter_version` | string | `"1.10.2"` | overridden by workflow input |
| `node_exporter_user` | string | `"node_exporter"` | system, non-login |
| `node_exporter_group` | string | `"node_exporter"` | system |
| `node_exporter_bind_address` | string | `"0.0.0.0"` | per Q1 clarification |
| `node_exporter_port` | integer | `9100` | 1024–65535 |
| `node_exporter_install_dir` | string | `"/opt/node_exporter"` | versioned subdirs underneath |
| `node_exporter_bin_path` | string | `"/usr/local/bin/node_exporter"` | symlink → versioned install |
| `node_exporter_download_url_base` | string | `"https://github.com/prometheus/node_exporter/releases/download"` | per FR-012 |
| `node_exporter_arch_map` | dict | `{ x86_64: amd64, aarch64: arm64 }` | maps `ansible_architecture` |
| `node_exporter_disabled_collectors` | list | `[]` | empty in v1; spec forbids extras |
| `node_exporter_enabled_collectors` | list | `[]` | empty in v1; defaults are used |

---

## Entity: Host Facts (gathered, not configured)

These are read-only inputs the role inspects on each host:

| Fact | Used for | Required value (else fail) |
| --- | --- | --- |
| `ansible_system` | platform check | `Linux` |
| `ansible_architecture` | binary selection | `x86_64` or `aarch64` |
| `ansible_distribution` | package manager hints | one of `{Ubuntu, Amazon, Debian, RedHat, Rocky, AlmaLinux}` |
| `ansible_service_mgr` | service module | `systemd` |
| `ansible_pkg_mgr` | future apt/dnf use (none in v1) | informational |

The `preflight.yml` task block asserts these and fails the host (not the play) on mismatch.

---

## Entity: Reconcile Run Result (JSON callback emitted at end of run)

File: `$RUNNER_TEMP/ansible-run.json` (read by `exit-code.sh`).

| Field | Type | Source |
| --- | --- | --- |
| `plays[*].play.name` | string | playbook structure |
| `stats.<hostname>.ok` | int | per-host count of `ok` results |
| `stats.<hostname>.changed` | int | per-host count of `changed` results |
| `stats.<hostname>.failures` | int | per-host count of task failures |
| `stats.<hostname>.unreachable` | int | per-host count of unreachable (SSM session failed) |
| `stats.<hostname>.skipped` | int | per-host count of skips |

`exit-code.sh` parses this with `jq` to compute the failure-threshold decision (FR-017) and emit the per-host summary to `$GITHUB_STEP_SUMMARY`.

---

## State transitions (per host)

```
[Unconverged] ──install.yml──▶ [Binary present, not running]
                                 │
                                 ├──service.yml──▶ [Active]
                                 │
                                 └──verify.yml──▶ [Verified Active]

[Verified Active] ──any drift──▶ [Drifted] ──next run──▶ [Verified Active]
[Verified Active] ──unchanged inputs──▶ [Verified Active] (zero changed)
```

The terminal state on every successful run is **Verified Active**. Idempotency (FR-005, SC-002) means once-Verified-Active hosts re-run as zero-changed.
