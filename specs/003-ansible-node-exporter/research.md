# Phase 0 Research: Ansible Node Exporter on SSM-Managed EC2

**Feature**: `003-ansible-node-exporter` · **Date**: 2026-05-17 · **Spec**: [spec.md](./spec.md)

This document resolves every NEEDS-CLARIFICATION item in the Technical Context and records each decision with rationale and alternatives considered. All findings are grounded in the actual repo, the upstream Ansible/AWS docs, and the upstream Node Exporter release.

---

## Decision 1 — Repo-state finding: tag schema on the live fleet differs from the spec selector

**Finding**: The EC2 instances provisioned by `aws/dev/<region>/bluemesh/ec2/terragrunt.hcl` via the `aws/terraform/modules/ec2-extended` module are tagged today with the merged tag set from `aws/root.hcl` plus the module's instance-level additions:

| Tag key | Tag value (today) | Source |
| --- | --- | --- |
| `Project` | `compute-ansible` | `aws/root.hcl` |
| `Account` | `dev` | `aws/root.hcl` |
| `Region` | `us-east-1` | `aws/root.hcl` |
| `Versionmesh` | `bluemesh` | `aws/root.hcl` |
| `ManagedBy` | `terragrunt` | `aws/root.hcl` |
| `Repo` | `next-signal/compute-ansible-machines` | `aws/root.hcl` |
| `Service` | `ec2-extended` | `aws/dev/us-east-1/bluemesh/ec2/terragrunt.hcl` |
| `Name` | `<computed>` | module |
| `DeployID` | `<git short SHA>` | module |
| `deployment_code` | `bluemesh-dev-us-east-1` | module |

The spec's clarified selector (`Environment=dev`, `ManagedBy=ansible`, `Process=monitoring`, `version=blue`, `Owner=<repo>`) does **not** match the live tags. None of `Environment`, `Process`, `version`, or `Owner` exist on the instances today; `ManagedBy` exists but is `terragrunt`, not `ansible`.

**Decision**: Use a **two-key adapter selector** for v1 that maps cleanly to the live tag schema while preserving the spec's intent:

- `Project=compute-ansible` (constitutional principle I; identifies the platform)
- `Versionmesh=bluemesh` (blue/green slot — replaces `version=blue`)
- `Account=dev` (replaces `Environment=dev`)
- `Service=ec2-extended` (replaces `Process=monitoring` — currently the *only* EC2 service in this repo, so the workflow effectively targets the whole compute fleet, which matches user intent for "every EC2 machine I deploy")
- `instance-state-name=running`

**Rationale**: Adding new tags to the Terragrunt EC2 module is a constitutional change (Principle III: directory-as-contract) that should be a separate spec. Using the existing tag schema lets us ship v1 against the real fleet **today**, with zero infra changes required.

**Alternatives considered**:

- **Add the new tags to the EC2 module**: Cleanest spec-alignment, but it pulls in a Terragrunt change, a re-apply of the `aws/dev/us-east-1/bluemesh/ec2` component, and a constitutional review. Worth doing as a follow-up sub-topic branch (`003-ansible-node-exporter--align-tag-schema`), not v1.
- **Hard-code instance IDs into a static inventory**: Violates FR-003 (dynamic inventory only).
- **Use only `Project=compute-ansible` and `Account=dev`**: Too broad — would also pick up future non-EC2 resources if the module is ever reused. Adding `Service=ec2-extended` keeps it precise.

**Spec / FR-001 update required after plan acceptance**: re-word FR-001's default selector to the adapter set above and document `Process=monitoring` / `version=blue` / `Owner=<repo>` as the *future* (post-tag-schema-alignment) selector. This is the only spec amendment introduced by research.

---

## Decision 2 — IAM gaps the workflow will hit (must be addressed in a precondition sub-task)

**Finding**: Two IAM permission sets are missing from the current cloud setup. Both are precondition gaps, not part of the Ansible layer itself.

### 2a. GitHub Actions OIDC role (`GH_ROLE_DEV`) has no SSM/EC2-describe permissions

`aws/terraform/modules/oidc/main.tf` grants only:

- `eks_access` (out of scope here)
- `terragrunt_state` (S3 + DynamoDB for state)
- `infra_provisioning` (broad provisioning, plus a narrow `ssm:GetParameter` — **not** `ssm:StartSession` / `ssm:SendCommand` / `ssm:DescribeInstanceInformation`)

For Ansible to discover instances and connect, the OIDC role needs added permissions (least-privilege):

```hcl
# Inline policy to add to module "oidc" → resource "aws_iam_role_policy" "ansible_ssm"
Statement = [
  {
    Effect   = "Allow"
    Action   = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeVpcs",
      "ssm:DescribeInstanceInformation",
      "ssm:GetConnectionStatus",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession",
      "ssm:DescribeSessions",
      "ssm:DescribeInstanceProperties"
    ]
    Resource = "*"
  },
  {
    Effect   = "Allow"
    Action   = ["ssm:SendCommand", "ssm:GetCommandInvocation"]
    Resource = [
      "arn:aws:ec2:${local.region}:${local.account_id}:instance/*",
      "arn:aws:ssm:${local.region}:*:document/AWS-StartSSHSession",
      "arn:aws:ssm:${local.region}:*:document/AWS-StartNonInteractiveCommand",
      "arn:aws:ssm:${local.region}:*:document/SSM-SessionManagerRunShell"
    ]
  }
]
```

Plus the S3 permissions required by the connection plugin — see 2c.

### 2b. EC2 instance profile has no S3 write permission to the SSM-transfer bucket

`aws/terraform/modules/ec2-extended/main.tf` attaches only `AmazonSSMManagedInstanceCore` to `aws_iam_role.instance`. Per the [`amazon.aws.aws_ssm` plugin docs](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ssm_connection.html), **even `shell` and `command` modules require S3** because Ansible ships its module `.py` files via S3 (the SSM session only carries the `curl` call that pulls them down via a presigned URL). The instance profile must be allowed to GET objects from the staging bucket (the plugin generates the presigned URL on the controller, so the instance only needs no-IAM access to the URL — but if the bucket has a strict policy, the instance principal still needs allow).

Pragmatic option: **make the bucket's resource policy allow access from the EC2 instance role principal** rather than touch the instance profile. This keeps `ec2-extended` unchanged.

### 2c. Controller (OIDC role) needs S3 perms on the staging bucket

Per plugin docs, the controller must be able to `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, `s3:DeleteObject`, `s3:GetBucketLocation` against the chosen bucket. This goes in the OIDC role inline policy.

### 2d. Where does the staging bucket itself come from?

**Decision**: Provision the staging bucket via Terragrunt as a new shared component at `aws/dev/shared/ansible-ssm-bucket/`, following the directory-as-contract pattern (constitutional principle III). Bucket name: `compute-ansible-${account_id}-${region}-ansible-ssm`. Versioning disabled (per plugin docs — versioning preserves secrets sent through the bucket). Lifecycle rule: expire any object older than 1 day to guard against ungraceful playbook exits leaving residue.

**Rationale**: A new bucket is the cleanest fit for both the constitution (resource lives in IaC, tagged, per-environment-isolated) and the plugin's requirements. Putting it under `shared/` would conflate it with admin-only OIDC config; putting it at the `account/region` level matches the bucket's actual scope.

**Alternatives considered**:

- **Reuse the existing Terragrunt state bucket** (`compute-ansible-${region}-${environment}`): Tempting, but mixing application-runtime artifact transfer with Terraform state in one bucket is a bad coupling (state is sensitive; rotating the bucket policy or accidentally pointing Ansible at the wrong prefix risks state corruption).
- **Bypass S3 via `amazon.aws.aws_ssm_send_command` module + `Run Command`**: This is *not* a connection-plugin replacement — it can ship one-shot commands but not run a full playbook with the module/handler model. Out of scope for v1.

### Action item for v1

These IAM/S3 gaps are **preconditions**, not Ansible-layer work. They will be a sub-topic branch (`003-ansible-node-exporter--iam-and-bucket`) that produces a small Terraform change. The Ansible workflow will be gated on those resources existing — checked at workflow start (`aws sts get-caller-identity` + `aws s3 ls s3://<bucket>` + `aws ssm describe-instance-information`).

---

## Decision 3 — Ansible runtime versions

**Decision**: Pin in CI:

- `ansible-core==2.17.*` (current stable in 2026, supports Python 3.10–3.12 controllers)
- `amazon.aws==10.*` (current stable; introduced `s3_addressing_style`, `bucket_endpoint_url`, `ssm_document` options used here)
- `community.general==9.*` (only for `community.general.json_query` if needed in templates)
- AWS Session Manager Plugin (the `session-manager-plugin` binary) — install from the AWS-provided `.deb` on the GitHub Actions runner.
- Python `boto3>=1.34`, `botocore>=1.34`

**Rationale**: 10.x is the current `amazon.aws` major; pinning to the line (not a specific patch) avoids stale collection bugs while still being reproducible enough for v1. `ansible-core` 2.17 is the lowest version that supports the 10.x collection's expected `ansible-core` floor.

**Alternatives considered**:

- **Use `ansible` (the meta-package) instead of `ansible-core` + selective collections**: Faster to install, but bigger, slower, and pulls in collections we will never use. We only need `amazon.aws` and (optionally) `community.general`.
- **Don't pin the collection version**: Risk of nondeterministic CI builds. Rejected.

---

## Decision 4 — Connection plugin choice and configuration

**Decision**: Use `amazon.aws.aws_ssm` (current canonical SSM connection plugin) and configure via inventory `compose`:

```yaml
compose:
  ansible_connection: "'aws_ssm'"
  ansible_aws_ssm_region: "'us-east-1'"
  ansible_aws_ssm_bucket_name: "'compute-ansible-${account_id}-us-east-1-ansible-ssm'"
  ansible_aws_ssm_bucket_sse_mode: "'AES256'"
  ansible_aws_ssm_s3_addressing_style: "'virtual'"
hostnames:
  - instance-id
```

`hostnames: instance-id` is mandatory — SSM addresses managed instances by ID, not IP/DNS.

**Rationale**: This is the documented, supported pattern. `community.aws.aws_ssm` is a redirect to `amazon.aws.aws_ssm`; using the canonical name is correct.

---

## Decision 5 — Default Node Exporter version and download path

**Decision**: Default `node_exporter_version: "1.10.2"` (verified current latest as of 2025-10-25 via [GitHub releases API](https://api.github.com/repos/prometheus/node_exporter/releases/latest)).

Download pattern:

- Tarball: `https://github.com/prometheus/node_exporter/releases/download/v{{ ver }}/node_exporter-{{ ver }}.linux-{{ arch }}.tar.gz`
- Checksum: `https://github.com/prometheus/node_exporter/releases/download/v{{ ver }}/sha256sums.txt`

Where `{{ arch }}` ∈ `{amd64, arm64}` (derived from `ansible_architecture` → mapped via a role-level `node_exporter_arch_map`).

**Rationale**: Both files are released atomically per tag, the checksum format (`<sha256>  <filename>` lines) is grep-able, and the GitHub release URLs are stable.

**Alternatives considered**:

- **Distro packages (`apt install prometheus-node-exporter`)**: Available, but stale on every distro; mixes config conventions (some use `/var/lib/node_exporter`, some `/etc/prometheus`); the upstream binary is universally consistent. Rejected.
- **Snap / container**: Adds a runtime dependency. Rejected.

---

## Decision 6 — Role structure (separation of concerns + future eBPF reuse)

**Decision**: One role: `roles/node_exporter`, structured as:

```text
roles/node_exporter/
├── defaults/main.yml      # version, port, user, arch map (overridable)
├── handlers/main.yml      # systemctl daemon-reload + restart on cfg/binary change
├── tasks/
│   ├── main.yml           # entrypoint; imports below in order
│   ├── preflight.yml      # arch detect, fail on unsupported, fact gathering
│   ├── user.yml           # create node_exporter system user (idempotent)
│   ├── install.yml        # download tarball + sha256sums.txt, verify, unpack
│   ├── service.yml        # systemd unit template, enable, start
│   └── verify.yml         # http GET /metrics on 127.0.0.1:port (no external dep)
├── templates/
│   └── node_exporter.service.j2
└── README.md
```

**Rationale**: One role per concern, tasks split into 5 small files for readability and so each can be skipped via `tags:` for fast iteration. The verify step uses `127.0.0.1` so it works on hosts with strict SG and doesn't depend on the SG actually being open from the runner.

**Alternatives considered**:

- **Galaxy role `cloudalchemy.node_exporter` / `prometheus-community.prometheus.node_exporter`**: Mature and well-tested, but pulls in features we don't need (multiple text-collector configs, TLS, multiple authentication options), adds an external dependency we'd have to pin and audit, and makes the role harder to mentally model on first contact. Spec explicitly forbids TLS / extra collectors. Rejected for v1, can revisit.
- **One big `main.yml`**: Cleaner top-down but harder to skip phases during iteration.

---

## Decision 7 — Workflow exit-code strategy (FR-017)

**Decision**: Implement trigger-aware failure semantics with two Ansible features:

- Use `--limit '!unreachable'` plus a post-play `set_fact: host_failed=...` to classify per-host outcomes.
- After `ansible-playbook` exits, parse the JSON callback (`ANSIBLE_STDOUT_CALLBACK=ansible.builtin.json` + redirected to a file) to compute `unreachable_hosts`, `failed_hosts`, `total_targeted`. Then:

```bash
if [[ "$TRIGGER" == "push" || "$TRIGGER" == "workflow_dispatch" ]]; then
  [[ $failed_hosts -gt 0 || $unreachable_hosts -gt 0 ]] && exit 1
else  # schedule
  pct=$(( failed_hosts * 100 / total_targeted ))
  [[ $unreachable_hosts -gt 0 || $pct -gt $THRESHOLD ]] && exit 1
fi
```

This logic lives in a small bash script (`ansible/scripts/exit-code.sh`) called as a final step, plus a `$GITHUB_STEP_SUMMARY` writer that always emits per-host results regardless of exit code.

**Rationale**: Keeps the playbook itself fail-fast on each task while moving the *workflow-level* decision into a small, testable shell helper. Avoids inventing custom Ansible plugins for v1.

**Alternatives considered**:

- **`any_errors_fatal: true`**: Aborts on first failure on any host — too strict; spec wants partial-fleet recovery.
- **A custom Ansible stats callback**: More elegant, more code; not justified for v1.

---

## Decision 8 — `just` recipe surface (constitutional principle V)

**Decision**: Add to `justfile`:

```just
# --- Ansible Operations ---

# Install Ansible deps locally (idempotent)
ansible-setup:
    cd ansible && python -m pip install -r requirements.txt && \
    ansible-galaxy collection install -r requirements.yml

# List discovered targets (read-only, requires AWS creds)
ansible-inventory account region versionmesh:
    cd ansible && \
    ANSIBLE_AWS_ENV={{account}} ANSIBLE_AWS_REGION={{region}} ANSIBLE_AWS_VERSIONMESH={{versionmesh}} \
    ansible-inventory -i inventories/aws/dynamic.aws_ec2.yml --list

# Syntax-check all playbooks
ansible-check:
    cd ansible && ansible-playbook --syntax-check playbooks/install-node-exporter.yml
    cd ansible && ansible-lint playbooks/ roles/

# Dry-run (check mode + diff) — does not change anything
ansible-plan account region versionmesh:
    cd ansible && \
    ANSIBLE_AWS_ENV={{account}} ANSIBLE_AWS_REGION={{region}} ANSIBLE_AWS_VERSIONMESH={{versionmesh}} \
    ansible-playbook -i inventories/aws/dynamic.aws_ec2.yml playbooks/install-node-exporter.yml --check --diff

# Real apply (use through CI usually; locally only for emergency reconcile)
ansible-apply account region versionmesh:
    cd ansible && \
    ANSIBLE_AWS_ENV={{account}} ANSIBLE_AWS_REGION={{region}} ANSIBLE_AWS_VERSIONMESH={{versionmesh}} \
    ansible-playbook -i inventories/aws/dynamic.aws_ec2.yml playbooks/install-node-exporter.yml
```

**Rationale**: Mandatory under constitutional principle V ("automation via just"). CI calls these recipes, not raw `ansible-playbook`. Local emergency reconcile remains possible.

---

## Decision 9 — GitHub Actions workflow shape (mirrors existing `aws-infra-*` workflows)

**Decision**: New workflow `.github/workflows/ansible-node-exporter.yaml` mirrors the structure of `aws-infra-provision.yaml`:

- `permissions: id-token: write, contents: read`
- Same OIDC role assumption pattern (`GH_ROLE_DEV` / `GH_ROLE_PROD` via `aws-actions/configure-aws-credentials@v4`)
- Same `PROFILE_NAME: devops-compute-ansible` setup
- Concurrency group: `ansible-node-exporter-${{ inputs.account || 'dev' }}-${{ inputs.region || 'us-east-1' }}-${{ inputs.versionmesh || 'bluemesh' }}` with `cancel-in-progress: false` (FR-018; matches existing `aws-${account}-${region}-${versionmesh}` pattern)
- Triggers: `push: branches: [main]` (paths-filtered to `ansible/**`), `workflow_dispatch`, `schedule: '17 * * * *'` (one minute offset off the hour to avoid cron herd)
- Job calls `just ansible-setup` → `just ansible-check` → `just ansible-apply`, then the exit-code helper

**Rationale**: Consistency with the existing platform workflows. Operator onboarding is zero new patterns.

---

## Decision 10 — Out-of-scope items reconfirmed (defensive against scope creep)

These are NOT part of v1, captured here so `/tasks` doesn't drift:

- **eBPF agent** (FR-015). Will be `004-rust-ebpf-agent` or a sub-topic later.
- **AMI baking with Packer**. Future maturity step per prior conversation.
- **TLS on Node Exporter**, basic auth, textfile collector, custom collectors.
- **A Prometheus instance / scrape registry**. Producing `/metrics` is the boundary.
- **Multi-account / cross-account SSM**. Single account (`dev`) only.
- **The `prod` environment**. Spec is `dev`-only; promotion is a follow-up.
- **Adding new tags to `ec2-extended`** (see Decision 1). Sub-topic branch.
- **Air-gapped binary sourcing / S3 mirror of Node Exporter** (FR-012 clarification confirms upstream only).

---

## Open NEEDS-CLARIFICATION — none

All Phase 0 unknowns resolved.
