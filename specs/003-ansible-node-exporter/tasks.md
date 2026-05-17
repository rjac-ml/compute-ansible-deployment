# Tasks: Ansible Node Exporter on SSM-Managed EC2

**Input**: Design documents from `/specs/003-ansible-node-exporter/`
**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Not requested — and not used in v1. The "test surface" is `ansible-playbook --check --diff`, the role's `verify.yml` task file, and the manual acceptance tests in `quickstart.md`. No `tests/` tree is created (see plan.md §Structure Decision).

**Organization**: Tasks are grouped by user story (US1–US4 from `spec.md`). The MVP is **US1 + US2** (both P1 — Story 2's idempotency is what makes Story 1 safe to re-run).

**Two-branch execution model** (see `plan.md` §Implementation phasing):

- **Phase 1 (Setup)** + **Phase 2 (Foundational)** here are **executed on a separate sub-topic branch** `003-ansible-node-exporter--iam-and-bucket`, opened *off* this branch, applied locally by an admin (Principle II for shared OIDC), and merged back **before** any User Story phase can run end-to-end.
- **Phases 3–6 (User Stories + Polish)** execute on this branch `003-ansible-node-exporter`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Maps task to user story (US1, US2, US3, US4) — Setup/Foundational/Polish have no story label
- Include exact file paths in descriptions

## Path Conventions

This is an infrastructure / configuration-management repo, not an application repo. Paths reflect the layout fixed in `plan.md` §Source Code:

- Ansible layer: `ansible/` (top-level, NEW)
- Terraform modules: `aws/terraform/modules/<name>/`
- Terragrunt configs: `aws/<account>/<region>/<component>/`
- CI workflows: `.github/workflows/`
- Task wrapper: `justfile` (root, APPEND)

---

## Phase 1: Setup (Sub-topic branch — `003-ansible-node-exporter--iam-and-bucket`)

**Purpose**: Open a sub-topic branch and prepare the directory + module scaffolding for the precondition work. Admin-only apply (Principle II governs `aws/dev/shared/oidc/`).

**⚠️ Execution location**: Sub-topic branch only. Do NOT add these files to `003-ansible-node-exporter`.

- [ ] T001 From `003-ansible-node-exporter`, create sub-topic branch `003-ansible-node-exporter--iam-and-bucket` (`git checkout -b 003-ansible-node-exporter--iam-and-bucket`)
- [ ] T002 [P] Create empty module directory `aws/terraform/modules/ansible-ssm-bucket/` with placeholder files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- [ ] T003 [P] Create empty Terragrunt config directories `aws/dev/us-east-1/ansible-ssm-bucket/` and `aws/dev/us-east-2/ansible-ssm-bucket/` each containing a `terragrunt.hcl` placeholder

---

## Phase 2: Foundational — Preconditions (Sub-topic branch, BLOCKING)

**Purpose**: Land the two precondition gaps surfaced in `research.md` Findings 1 & 2 — the S3 staging bucket (mandatory for `amazon.aws.aws_ssm`) and the OIDC IAM additions (SSM + EC2-describe + S3-read perms). Apply locally by admin; merge to `main`; then `003-ansible-node-exporter` can proceed.

**⚠️ CRITICAL**: No User Story work in this branch can run end-to-end until this phase is complete, merged, and applied to AWS dev.

### S3 staging bucket (Terraform module — for SSM file transfer)

- [ ] T004 Implement S3 bucket module body in `aws/terraform/modules/ansible-ssm-bucket/main.tf`: bucket name `compute-ansible-${var.account_id}-${var.region}-ansible-ssm`, versioning **OFF**, lifecycle expiry **1 day**, block-public-access ON, SSE-S3 default encryption, and a bucket policy granting `s3:GetObject` / `s3:PutObject` / `s3:DeleteObject` / `s3:ListBucket` to the EC2 instance profile role ARN passed as `var.ec2_instance_role_arn`
- [ ] T005 [P] Declare inputs in `aws/terraform/modules/ansible-ssm-bucket/variables.tf` (`account_id`, `region`, `ec2_instance_role_arn`, optional `tags`)
- [ ] T006 [P] Declare outputs in `aws/terraform/modules/ansible-ssm-bucket/outputs.tf` (`bucket_name`, `bucket_arn`)
- [ ] T007 [P] Pin providers in `aws/terraform/modules/ansible-ssm-bucket/versions.tf` matching the rest of `aws/terraform/modules/*/versions.tf`

### Terragrunt config (per-region — bucket lifecycle is CI-managed, not admin-only)

- [ ] T008 [P] Write `aws/dev/us-east-1/ansible-ssm-bucket/terragrunt.hcl` referencing the new module, passing `account_id`, `region`, and the `ec2-extended` instance-role ARN via remote-state lookup (use the existing `dependency` pattern from neighboring `aws/dev/us-east-1/bluemesh/ec2/terragrunt.hcl`)
- [ ] T009 [P] Write `aws/dev/us-east-2/ansible-ssm-bucket/terragrunt.hcl` (same content as T008 with `region = us-east-2`)

### OIDC IAM additions (admin-only — modifies `aws/dev/shared/oidc/`)

- [ ] T010 Open `aws/terraform/modules/oidc/main.tf` and **append** an inline policy / managed-policy attachment to the existing OIDC-assumable role that grants: `ssm:StartSession`, `ssm:SendCommand`, `ssm:DescribeInstanceInformation`, `ssm:GetCommandInvocation`, `ssm:TerminateSession`, `ec2:DescribeInstances`, `ec2:DescribeInstanceStatus`, plus `s3:GetObject`/`PutObject`/`DeleteObject`/`ListBucket` scoped to the `compute-ansible-*-ansible-ssm` bucket pattern. Do NOT remove or alter the existing `ssm:GetParameter` permission.

### Local apply by admin (Principle II — admin-only path)

- [ ] T011 Admin applies the bucket Terragrunt configs locally: `cd aws/dev/us-east-1/ansible-ssm-bucket && terragrunt apply` and again for `us-east-2`
- [ ] T012 Admin applies the OIDC changes locally: `cd aws/dev/shared/oidc && terragrunt apply` (this is admin-only by repo convention; the new OIDC permissions are what enable Ansible to run in CI thereafter)
- [ ] T013 Verify the new IAM policy is attached to the OIDC role: `aws iam list-attached-role-policies --role-name <role-name-from-output>` returns the new entries; and `aws s3 ls s3://compute-ansible-<account-id>-us-east-1-ansible-ssm` succeeds with the OIDC role
- [ ] T014 Open PR for `003-ansible-node-exporter--iam-and-bucket` → `main`, merge after admin review, then `git checkout 003-ansible-node-exporter` and `git rebase main`

**Checkpoint**: Preconditions are live in AWS dev. The Ansible layer can now be built on `003-ansible-node-exporter`.

---

## Phase 3: User Story 1 — Push-triggered install on a fresh fleet (Priority: P1) 🎯 MVP

**Goal**: After Terragrunt has provisioned tagged EC2 instances, pushing a commit to `main` causes GitHub Actions to run Ansible over SSM, install Node Exporter v1.10.2, and bring the systemd unit to `active (running)` on port 9100.

**Independent Test** (per `spec.md` US1): On a fresh, correctly tagged single-host fleet, push a commit to `main`. The workflow run finishes green. From inside the VPC, `curl http://<instance>:9100/metrics` returns HTTP 200 with `node_*` series. Maps to acceptance scenarios US1.1, US1.2, US1.3 and to `quickstart.md` AT-1, AT-2, AT-3.

### Ansible layer scaffolding (this branch — `003-ansible-node-exporter`)

- [ ] T015 [P] [US1] Create `ansible/ansible.cfg` pinning `stdout_callback=yaml`, `gathering=smart`, enabling `amazon.aws.aws_ec2` and `amazon.aws.aws_ssm` plugins, `host_key_checking=False` (SSM does not use SSH keys but Ansible reads the flag), and `retry_files_enabled=False`
- [ ] T016 [P] [US1] Create `ansible/requirements.txt` pinning `ansible-core==2.17.*`, `boto3>=1.34`, `botocore>=1.34`
- [ ] T017 [P] [US1] Create `ansible/requirements.yml` pinning `amazon.aws==10.*` and `community.general==9.*` Galaxy collections
- [ ] T018 [P] [US1] Create `ansible/README.md` (operator doc) covering layer purpose, local-vs-CI usage, and pointer to `quickstart.md`

### Dynamic inventory (SSM-only, no SSH)

- [ ] T019 [US1] Create `ansible/inventories/aws/dynamic.aws_ec2.yml` using the `amazon.aws.aws_ec2` plugin with: `regions: [us-east-1]`, `hostnames: [instance-id]` (mandatory for SSM), `filters` set to the **adapter selector** from `research.md` Finding 1 (`tag:Project=compute-ansible`, `tag:Account=dev`, `tag:Versionmesh=bluemesh`, `tag:Service=ec2-extended`, `instance-state-name=running`), `keyed_groups` by versionmesh and region, and `compose:` setting `ansible_connection=aws_ssm`, `ansible_aws_ssm_bucket_name`, `ansible_aws_ssm_region`. Selector keys MUST be overridable via `--extra-vars` per `contracts/role-interface.md`

### `node_exporter` role — defaults + handlers + templates

- [ ] T020 [P] [US1] Create `ansible/roles/node_exporter/defaults/main.yml` exposing every overridable variable listed in `contracts/role-interface.md` (`node_exporter_version: "1.10.2"`, `node_exporter_listen_address: "0.0.0.0"`, `node_exporter_listen_port: 9100`, `node_exporter_user: "node_exporter"`, `node_exporter_group: "node_exporter"`, `node_exporter_install_dir: "/usr/local/bin"`, `node_exporter_download_base_url: "https://github.com/prometheus/node_exporter/releases/download"`, `node_exporter_checksum_file: "sha256sums.txt"`)
- [ ] T021 [P] [US1] Create `ansible/roles/node_exporter/handlers/main.yml` with a single `restart node_exporter` handler that runs `systemctl daemon-reload` then `systemctl restart node_exporter`
- [ ] T022 [P] [US1] Create `ansible/roles/node_exporter/templates/node_exporter.service.j2` — minimal systemd unit: `User={{ node_exporter_user }}`, `Group={{ node_exporter_group }}`, `ExecStart={{ node_exporter_install_dir }}/node_exporter --web.listen-address={{ node_exporter_listen_address }}:{{ node_exporter_listen_port }}`, `Restart=on-failure`, `NoNewPrivileges=true`, `ProtectSystem=strict`, `ProtectHome=true`, `WantedBy=multi-user.target`
- [ ] T023 [P] [US1] Create `ansible/roles/node_exporter/README.md` documenting variables, handlers, the role's idempotency contract from `contracts/role-interface.md`

### `node_exporter` role — task files (ordered, idempotent)

- [ ] T024 [US1] Create `ansible/roles/node_exporter/tasks/main.yml` that includes the five task files in order: `preflight.yml`, `user.yml`, `install.yml`, `service.yml`, `verify.yml`
- [ ] T025 [US1] Create `ansible/roles/node_exporter/tasks/preflight.yml` — gather facts; map `ansible_architecture` (`x86_64`→`amd64`, `aarch64`→`arm64`); `fail:` with a clear message for any other architecture (per FR-010, edge-case #8); set fact `node_exporter_arch`
- [ ] T026 [US1] Create `ansible/roles/node_exporter/tasks/user.yml` — `ansible.builtin.group` then `ansible.builtin.user` to create `node_exporter` system user/group as non-login (`shell: /usr/sbin/nologin`, `system: true`, `create_home: false`); idempotent so re-runs report `ok` (FR-005)
- [ ] T027 [US1] Create `ansible/roles/node_exporter/tasks/install.yml` — download `sha256sums.txt` from `{{ node_exporter_download_base_url }}/v{{ node_exporter_version }}/{{ node_exporter_checksum_file }}` to a temp file; extract the entry for `node_exporter-{{ node_exporter_version }}.linux-{{ node_exporter_arch }}.tar.gz`; download the tarball with `ansible.builtin.get_url` passing `checksum: "sha256:<value>"` so a mismatch fails the task (FR-012); `ansible.builtin.unarchive` to a temp dir; `ansible.builtin.copy` the extracted `node_exporter` binary to `{{ node_exporter_install_dir }}/node_exporter` with `mode: 0755`, `owner: root`, `group: root`, and `force: yes` only when the on-disk binary's sha256 differs (use `creates:` or a `stat` + `when:` guard so re-runs report `ok`)
- [ ] T028 [US1] Create `ansible/roles/node_exporter/tasks/service.yml` — `ansible.builtin.template` rendering `node_exporter.service.j2` to `/etc/systemd/system/node_exporter.service` (notify `restart node_exporter`); `ansible.builtin.systemd` ensure `enabled: true`, `state: started`, `daemon_reload: true`
- [ ] T029 [US1] Create `ansible/roles/node_exporter/tasks/verify.yml` — `ansible.builtin.systemd` check that the service is `active`; `ansible.builtin.uri` GET `http://127.0.0.1:{{ node_exporter_listen_port }}/metrics` expecting HTTP 200 and a body containing `node_exporter_build_info`; fail the host loudly otherwise (FR-011)

### Playbook entry point

- [ ] T030 [US1] Create `ansible/playbooks/install-node-exporter.yml` — single play targeting `hosts: aws_ec2`, `gather_facts: true`, `become: true`, `become_method: sudo`, `serial: 25%` to limit blast radius; `roles: [node_exporter]`. Force `any_errors_fatal: false` so a single host failure does not kill the run (FR-013, edge-case #6)

**Checkpoint**: At this point, an operator with the preconditions applied can run `ansible-playbook -i ansible/inventories/aws/dynamic.aws_ec2.yml ansible/playbooks/install-node-exporter.yml` locally against `bluemesh` dev and watch Node Exporter come up on every matching host. US1 is functionally complete *locally*. CI integration follows in Phases 4 + 5.

---

## Phase 4: User Story 2 — Idempotent reconciliation on re-run (Priority: P1)

**Goal**: A second consecutive run against an unchanged, already-converged fleet produces `0 changed` across every task on every host, and the service is not restarted. Drift on a single host (service stopped, binary missing) is corrected automatically on the next run.

**Independent Test** (per `spec.md` US2): Run the playbook twice against the same fleet. Second run reports `ok=N changed=0 unreachable=0 failed=0` for every host. Then `systemctl stop node_exporter` on one host, re-run, and that host reports `changed` (service restart) while every other host stays `0 changed`. Then `rm /usr/local/bin/node_exporter` on one host, re-run, and the binary is redeployed.

US2 is **mostly delivered by the design of the US1 tasks** (every `install.yml` / `user.yml` / `service.yml` task is already written with explicit idempotency guards). The tasks below are the **specific verification + tightening work** that proves and protects that guarantee.

### Idempotency hardening

- [ ] T031 [US2] Audit `ansible/roles/node_exporter/tasks/install.yml` (T027) so the tarball download + unarchive steps are guarded with `creates:` (or equivalent `when: not <stat>.stat.exists`) — re-runs MUST NOT re-download the tarball when the on-disk binary's sha256 already matches the expected upstream sha256
- [ ] T032 [US2] Audit `ansible/roles/node_exporter/tasks/service.yml` (T028) so the `template:` task only notifies the `restart node_exporter` handler when the rendered unit file actually changes (default `template:` behavior — verify the unit content is byte-stable across runs; no embedded timestamps, no `{{ ansible_date_time }}` in the template)
- [ ] T033 [US2] Add a `tasks/verify.yml` (T029) post-check that records the service's `MainPID` via `systemctl show -p MainPID` and `set_fact` registers it — used as a diagnostic in logs, not as a fail condition, but makes the "PID unchanged on re-run" claim from acceptance scenario US2.1 visible

### Self-healing drift

- [ ] T034 [US2] Verify `ansible/roles/node_exporter/tasks/service.yml` (T028) uses `state: started` (not `state: restarted`) so a running service is not bounced, but a stopped service IS started — this is what makes acceptance scenario US2.2 work
- [ ] T035 [US2] Verify `ansible/roles/node_exporter/tasks/install.yml` (T027) will re-deploy the binary if it's missing on disk (the `creates:`/`stat` guard from T031 should naturally cover this — confirm via a manual `rm` + re-run during validation in Phase 6)

**Checkpoint**: US1 + US2 together form the MVP. With Phase 2 preconditions applied + Phases 3 + 4 implemented, the feature is shippable *if* invoked from a local workstation. Phase 5 wires it into CI.

---

## Phase 5: User Story 3 — Version upgrade by editing one value (Priority: P2)

**Goal**: Bumping `node_exporter_version` in role defaults from one value to another causes the next run to install the new binary, restart the service, and converge — and the subsequent run reports `0 changed`.

**Independent Test** (per `spec.md` US3): Set `node_exporter_version: "1.10.1"` initially, run, converge. Change to `1.10.2`, run again: the install task reports `changed` on every host (new binary), the service restarts, verify task passes. Third run: `0 changed` everywhere.

US3 is also **mostly delivered by US1's task design** (the variable is already overridable per `contracts/role-interface.md`). The work below is the version-aware diff logic.

- [ ] T036 [US3] Confirm `ansible/roles/node_exporter/tasks/install.yml` (T027) uses the **expected upstream sha256** from the resolved `sha256sums.txt` as the trigger for "is the on-disk binary out of date?" — when the version variable changes, the expected sha256 changes, the on-disk sha256 no longer matches, and the binary is replaced. Add an explicit `stat` + `command: sha256sum` comparison if the `creates:` guard alone is not version-aware
- [ ] T037 [US3] Confirm the `restart node_exporter` handler (T021) is notified by the binary-copy task (T027), so a binary swap triggers a service restart on the same run — required for US3 acceptance scenario US3.1
- [ ] T038 [US3] Document the upgrade procedure in `ansible/README.md` (T018): "to upgrade the fleet, edit `node_exporter_version` in `ansible/roles/node_exporter/defaults/main.yml`, commit, push to `main`; the workflow will roll it out"

**Checkpoint**: US3 is complete. The fleet can be upgraded by a one-line PR.

---

## Phase 6: User Story 4 — Scoped run with manual dispatch (Priority: P3)

**Goal**: Operator clicks "Run workflow" with a tag override (e.g., narrow to a specific `Name` tag or instance ID) and only that subset is touched.

**Independent Test** (per `spec.md` US4): With 3 matching instances in the fleet, dispatch the workflow with an override input narrowing to one instance ID. Workflow runs against that single instance only; the other two are untouched.

US4 depends on the workflow being in place (Phase 5 tasks below are shared with the CI work). It is implemented as **workflow inputs that override the inventory filters**, per `contracts/workflow-inputs.schema.yaml`.

- [ ] T039 [US4] In the inventory file `ansible/inventories/aws/dynamic.aws_ec2.yml` (T019), confirm every filter key is parameterized by a variable that can be overridden via `--extra-vars` on the `ansible-playbook` invocation (`tag_project`, `tag_account`, `tag_versionmesh`, `tag_service`, `instance_state`, optional `tag_name`, optional `instance_ids`)
- [ ] T040 [US4] Document the override mechanism in `ansible/README.md` (T018): table of every overridable key + an example `--extra-vars` invocation that narrows to a single instance

(The actual CI wiring of US4's `workflow_dispatch` inputs lives in Phase 7 below — that's where the GH Actions inputs map onto these `--extra-vars`.)

**Checkpoint**: All four user stories are independently functional. Phase 7 makes the loop CI-driven.

---

## Phase 7: Automation & CI Integration (Cross-Cutting)

**Purpose**: Wrap the Ansible layer in `just` recipes and a GitHub Actions workflow so the feature is invoked the way `001` / `002` features are invoked, not by raw `ansible-playbook` commands. This phase is what turns "it works from my laptop" into "it works as a continuous reconciler" and is required for spec acceptance.

### `justfile` recipes (Principle V)

- [ ] T041 Append to root `justfile` a new section `# ----- ansible -----` with 5 recipes following the existing `<provider>-<verb> account region versionmesh` shape: `ansible-setup` (creates venv, installs `ansible/requirements.txt`, `ansible-galaxy install -r ansible/requirements.yml`, downloads AWS Session Manager Plugin), `ansible-inventory account region versionmesh` (`ansible-inventory --graph` with extra-vars), `ansible-check account region versionmesh` (`--syntax-check` + `ansible-lint`), `ansible-plan account region versionmesh` (`--check --diff` dry run), `ansible-apply account region versionmesh` (real run). All recipes export `AWS_PROFILE=devops-compute-ansible` (matching existing pattern) and pass `--extra-vars` derived from the recipe args

### Workflow exit-code helper (FR-017 trigger-aware semantics)

- [ ] T042 Create `ansible/scripts/exit-code.sh` — bash helper that takes the path to the Ansible JSON callback output (set via `ANSIBLE_STDOUT_CALLBACK=json` + `ANSIBLE_CALLBACK_RESULT_FORMAT=json` or `--callback-plugin-dir`), reads `$GITHUB_EVENT_NAME` and `$FAILURE_THRESHOLD_PCT` from env. If event is `push` or `workflow_dispatch`: exit non-zero if any host has any failed task (strict mode per FR-017). If event is `schedule`: count `unreachable` hosts as hard-fail regardless of threshold; otherwise compute `failed_hosts / in_scope_hosts * 100`; exit non-zero only if that percentage exceeds `FAILURE_THRESHOLD_PCT` (default 20). Always write a markdown summary of per-host outcomes to `$GITHUB_STEP_SUMMARY` (FR-013, SC-007)

### GitHub Actions workflow

- [ ] T043 Create `.github/workflows/ansible-node-exporter.yaml` with: triggers `push` (paths: `ansible/**`, `.github/workflows/ansible-node-exporter.yaml`, branches: `main`), `workflow_dispatch` (inputs matching `contracts/workflow-inputs.schema.yaml`: `account`, `aws_region`, `versionmesh`, `tag_project`, `tag_account`, `tag_versionmesh`, `tag_service`, `tag_name` optional, `instance_ids` optional CSV, `node_exporter_version`, `failure_threshold_pct`), and `schedule` (`cron: "0 * * * *"` hourly). Enforce schema constraint: reject `account=prod` at job start (per data-model.md)
- [ ] T044 In the same workflow, declare the `concurrency` block: `group: ansible-node-exporter-${{ inputs.account || 'dev' }}-${{ inputs.aws_region || 'us-east-1' }}-${{ inputs.versionmesh || 'bluemesh' }}`, `cancel-in-progress: false` (per FR-018 + plan.md §Decision 8)
- [ ] T045 In the same workflow, declare permissions `id-token: write` and `contents: read` for OIDC; assume role via `aws-actions/configure-aws-credentials@v4` using secret `GH_ROLE_DEV` and `PROFILE_NAME: devops-compute-ansible` (matching existing workflows per `research.md` Finding "Existing repo patterns to mirror")
- [ ] T046 In the same workflow, install AWS Session Manager Plugin on the runner (`curl ... session-manager-plugin.deb && dpkg -i`), then run `just ansible-setup`, `just ansible-check dev us-east-1 bluemesh`, and (for non-dry-run triggers) `just ansible-apply dev us-east-1 bluemesh` piping JSON callback output to a file. Final step invokes `ansible/scripts/exit-code.sh` (T042) with the callback file + event name + threshold
- [ ] T047 [US4] Wire `workflow_dispatch` inputs into the `just ansible-apply` invocation as `--extra-vars` overrides (T039) — when `tag_name` or `instance_ids` is set, narrow the inventory; when `node_exporter_version` is set, override the role default. Document the inputs in the workflow file's `description:` fields so the GH Actions UI is self-explanatory

**Checkpoint**: The feature is fully CI-driven. Push to `main` triggers a run; hourly schedule reconciles; manual dispatch supports scoped runs (US4).

---

## Phase 8: Polish, Validation & Documentation

**Purpose**: Map the implementation back to `quickstart.md` acceptance tests, harden docs, and commit.

- [ ] T048 [P] Run `just ansible-check dev us-east-1 bluemesh` locally; fix any `ansible-lint` warnings; verify `--syntax-check` clean
- [ ] T049 [P] Run `just ansible-plan dev us-east-1 bluemesh` locally against a real bluemesh dev fleet (after Phase 2 preconditions are merged); capture the `--check --diff` output and paste into the PR description as "dry-run evidence"
- [ ] T050 Trigger the workflow via `gh workflow run ansible-node-exporter.yaml -f account=dev -f aws_region=us-east-1 -f versionmesh=bluemesh`; verify it converges per `quickstart.md` AT-1 through AT-9
- [ ] T051 Run a **second** `workflow_dispatch` immediately after T050 succeeds; verify the workflow summary shows `changed=0` for every host (proves US2 / SC-002)
- [ ] T052 Manually break one host (`aws ssm send-command ... 'systemctl stop node_exporter'`), wait for the next hourly schedule tick (or dispatch manually), verify the workflow exits **green** because only 1/N hosts is broken and N ≥ 5 (proves SC-007 + FR-017 schedule semantics); then verify the broken host is healed by the same run
- [ ] T053 [P] Update root `README.md` (or repo-level docs) with a one-line pointer to `ansible/README.md` and to `specs/003-ansible-node-exporter/quickstart.md`
- [ ] T054 [P] Run `.specify/scripts/bash/update-agent-context.sh claude` to refresh `CLAUDE.md` with the Ansible layer entries
- [ ] T055 Commit on `003-ansible-node-exporter`: stage `ansible/`, `.github/workflows/ansible-node-exporter.yaml`, `justfile`, `CLAUDE.md`, and the spec artifacts in `specs/003-ansible-node-exporter/`; commit with a Conventional-Commits message; open PR to `main`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup, sub-topic branch)**: No upstream dependencies — runs first.
- **Phase 2 (Foundational, sub-topic branch)**: Depends on Phase 1. **BLOCKS** every User Story that touches AWS end-to-end. Must merge to `main` and apply before Phase 3+ runs in CI.
- **Phase 3 (US1)**: Depends on Phase 2 being merged. Local-only completion possible after T029; CI completion requires Phase 7.
- **Phase 4 (US2)**: Depends on Phase 3 (US2 hardens US1's tasks). MVP = Phase 3 + Phase 4.
- **Phase 5 (US3)**: Depends on Phase 4 (idempotency contract must hold for version-aware diff to be meaningful).
- **Phase 6 (US4)**: Depends on Phase 3 (T019 inventory parameterization). Fully wired only after Phase 7 (T047).
- **Phase 7 (Automation)**: Depends on Phase 3 minimum (recipes/workflow must wrap an existing playbook). Can start in parallel with Phase 4/5/6 once Phase 3 is done.
- **Phase 8 (Polish)**: Depends on all desired user stories + Phase 7 being complete.

### User Story Dependencies (within this branch)

- **US1 (P1)**: Can start after Phase 2 merged.
- **US2 (P1)**: Builds directly on US1 — same task files. Independent in *test* (separate acceptance), shared in *code*.
- **US3 (P2)**: Builds on US1 + US2 — no separate files, just hardening + docs.
- **US4 (P3)**: Adds parameterization to T019 + new workflow inputs in T043/T047. Independent test surface.

### Within Each User Story

- Models / config / scaffolding before tasks
- Role task files in order: `preflight → user → install → service → verify`
- Role code before playbook before workflow
- Local invocation works before CI invocation

### Parallel Opportunities

- **Phase 1**: T002 and T003 are independent (different paths).
- **Phase 2**: T005, T006, T007 parallel after T004 lands the module skeleton; T008/T009 parallel (different region paths).
- **Phase 3**: T015, T016, T017, T018 all parallel (different files). T020, T021, T022, T023 parallel (different files within role scaffolding). T024–T029 are sequential (`main.yml` imports the others in order).
- **Phase 8**: T048, T049, T053, T054 parallel (different concerns / different files).

---

## Parallel Example: Phase 3 scaffolding

```bash
# Launch the four ansible-layer scaffolding files in parallel:
Task: "Create ansible/ansible.cfg per T015"
Task: "Create ansible/requirements.txt per T016"
Task: "Create ansible/requirements.yml per T017"
Task: "Create ansible/README.md per T018"

# Then launch the four role-scaffolding files in parallel:
Task: "Create roles/node_exporter/defaults/main.yml per T020"
Task: "Create roles/node_exporter/handlers/main.yml per T021"
Task: "Create roles/node_exporter/templates/node_exporter.service.j2 per T022"
Task: "Create roles/node_exporter/README.md per T023"
```

---

## Implementation Strategy

### MVP First (US1 + US2 — both P1)

1. Branch `003-...--iam-and-bucket` → Phase 1 + Phase 2 → admin apply → merge to `main`.
2. Rebase `003-ansible-node-exporter` onto `main`.
3. Phase 3 (US1) → Phase 4 (US2 hardening of the same files).
4. Phase 7 (T041–T046, minimum needed to invoke from CI).
5. Phase 8 acceptance tests AT-1 through AT-3 (US1) + AT-4 (US2 zero-changed re-run).
6. **STOP and VALIDATE**: at this point, the feature is shippable. US3 and US4 are improvements, not blockers.

### Incremental Delivery

1. MVP (US1 + US2 + minimum CI) → demo + merge as the v1 feature.
2. US3 (T036–T038) → version upgrades become a one-line PR.
3. US4 (T039–T040 + T047) → operators can scope runs from the Actions UI.
4. Polish (Phase 8 fully) → docs, repeated runs, edge-case validation.

### Constraints That Apply To Every Task

- **No SSH**, **no port 22**, **no static AWS keys** — anywhere. If a task generates code that introduces any of these, it MUST fail review.
- **No eBPF** (FR-015) — no `bpf*`, `cilium*`, `tetragon*`, `pixie*`, or kernel-probe references in any file produced by these tasks.
- **No kube/k8s/kubernetes naming** (FR-016) — applies to file names, role names, playbook names, workflow job names, inventory groups, tags, comments.
- **Ansible MUST NOT touch host firewall** (FR-004 + plan §Constraints) — no `firewalld`, `ufw`, `iptables`, `nftables` tasks. SG rules are Terragrunt-owned.
- **Idempotency** (FR-005) — every task that creates, downloads, copies, templates, or starts something MUST be guarded so re-runs report `ok`, not `changed`.

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks
- `[Story]` label maps task to specific user story for traceability
- The two-branch model (sub-topic for preconditions, main feature branch for the Ansible layer) is a deliberate constitutional choice — Principle II keeps OIDC mutations off the CI path
- The "Tests are optional" rule applies: no test files are generated. The verify task (T029) + dry-run (T049) + acceptance dispatches (T050–T052) are the test surface
- Avoid: same-file conflicts (already separated above), cross-story dependencies that break independence (US3 / US4 are explicitly designed to not block US1 / US2), introducing any of the constraint violations listed above
