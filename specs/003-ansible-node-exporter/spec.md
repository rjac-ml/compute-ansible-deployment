# Feature Specification: Ansible Node Exporter Install on SSM-Managed EC2 Fleet

**Feature Branch**: `003-ansible-node-exporter`
**Created**: 2026-05-16
**Status**: Draft
**Input**: User description: "Implement Ansible first but just the Node Exporter (no eBPF for now). Install Prometheus Node Exporter on each EC2 machine, reachable only via AWS SSM, automated from GitHub Actions, idempotent reconcile pattern."

## Clarifications

### Session 2026-05-17

- Q: How is the Node Exporter port 9100 exposed (bind address + firewall ownership)? → A: Bind to `0.0.0.0:9100`; Ansible does NOT manage any host-level firewall (`firewalld`/`ufw`/`iptables`). Network reachability is owned by Terragrunt-managed AWS security groups, which MUST allow inbound `9100/tcp` from inside the VPC CIDR only.
- Q: How should partial-fleet failures be reported across trigger types? → A: Trigger-aware. For `push` and `workflow_dispatch` runs, any host failure causes the workflow to exit non-zero (strict). For the `schedule` run, the workflow exits non-zero only if any host is fully SSM-unreachable OR more than 20% of in-scope hosts had any task failure; otherwise it exits zero with failures recorded in the run summary. The 20% threshold is a workflow input (default 20).
- Q: Where does the Node Exporter binary come from on each host? → A: Download directly from upstream GitHub releases (`https://github.com/prometheus/node_exporter/releases/download/v<ver>/...`) over HTTPS from each target host. Integrity is verified against the upstream `sha256sums.txt` published in the same release. No S3 mirror, no GitHub-runner-to-host file transfer, no fallback path in v1. Air-gapped / S3-mirror support is explicitly out of scope for this feature and will be a follow-up sub-topic branch if/when needed.
- Q: How are concurrent workflow runs against the same fleet prevented? → A: GitHub Actions `concurrency` group keyed on env + region (e.g. `nodeexp-${{ inputs.environment }}-${{ inputs.aws_region }}`) with `cancel-in-progress: false`. A second run (e.g. scheduled tick during a push run) queues instead of racing. No target-side locking and no external lock store.

## Scope Statement *(authoritative — read before everything else)*

This feature introduces the **first Ansible layer** in this repo for converging *software state* on existing AWS EC2 instances that are already provisioned by Terragrunt/Terraform under `aws/dev/...`. It explicitly addresses lesson #1 from spec `001` ("state what the module should and should NOT do up front").

**This feature does:**

- Install Prometheus Node Exporter as a `systemd`-managed service on Linux EC2 instances reachable via AWS SSM.
- Discover target instances dynamically from AWS by tags (no static inventories).
- Connect to instances over **AWS SSM Session Manager** only — no SSH, no port 22, no key management.
- Run via a GitHub Actions workflow triggered on push to `main`, manual dispatch, and an hourly schedule for drift reconciliation.
- Authenticate to AWS using the repo's existing GitHub OIDC pattern (no static keys).
- Be idempotent — re-running the workflow against an already-converged fleet reports zero changes.

**This feature does NOT:**

- Install, configure, or reference any eBPF agent. eBPF is explicitly out of scope and will be a follow-up spec.
- Build, bake, or publish AMIs. Image baking is a future maturity step, not part of this slice.
- Replace, modify, or duplicate any Terragrunt/Terraform module. Provisioning stays where it is.
- Enable Node Exporter TLS, basic auth, custom collectors, or textfile collectors. Defaults only.
- Set up Prometheus, a scrape target registry, alerting, or any consumer of the metrics. Producing `/metrics` on port 9100 is the boundary.
- Run Ansible from inside the EC2 fleet, from AWX/AAP, or from a long-lived controller VM. The controller is GitHub Actions only in this iteration.
- Use any naming containing "kube", "kubeadm", "k8s", or "kubernetes" (per the repo's no-kubernetes feedback rule).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Push-triggered install on a fresh fleet (Priority: P1)

As the infrastructure operator, after Terragrunt has just provisioned a set of EC2 instances tagged `Environment=dev`, `ManagedBy=ansible`, `Process=monitoring`, `version=blue`, and `Owner=compute-ansible-deployment` in `us-east-1`, I push a commit to `main` that introduces the Ansible layer. GitHub Actions runs, discovers the tagged instances over the AWS API, connects to each one via SSM, installs Node Exporter, deploys a `systemd` unit, starts the service, and reports success.

**Why this priority**: This is the entire MVP. Without it, the feature has no value. Every other story is a refinement of this loop.

**Independent Test**: Provision a single test EC2 with the required tags and IAM role, push the workflow to `main`, then verify from the operator's workstation (or any Prometheus instance) that `http://<instance>:9100/metrics` returns HTTP 200 with valid OpenMetrics text. The workflow run must end green.

**Acceptance Scenarios**:

1. **Given** a freshly provisioned EC2 instance tagged `Environment=dev`, `ManagedBy=ansible`, `Process=monitoring`, `version=blue`, `Owner=compute-ansible-deployment`, with the SSM Agent running and an instance profile granting `AmazonSSMManagedInstanceCore`, **When** a commit is merged to `main`, **Then** the GitHub Actions workflow runs Ansible over SSM, installs Node Exporter, and the service is `active (running)` on port 9100.
2. **Given** the workflow has just finished successfully, **When** the operator queries the instance metrics endpoint from inside the VPC, **Then** a valid `node_exporter` metrics response is returned and includes the standard `node_*` series.
3. **Given** zero matching instances exist (e.g., the tag filter returns nothing), **When** the workflow runs, **Then** it exits successfully with a clear "no targets matched" message rather than failing.

---

### User Story 2 — Idempotent reconciliation on re-run (Priority: P1)

As the same operator, I re-run the workflow against an already-converged fleet — either by pushing another unrelated change to `main`, by clicking "Run workflow", or by waiting for the hourly schedule to fire. Ansible should detect that everything is already in the desired state and produce a "0 changed" report.

**Why this priority**: Idempotency is the property that makes this whole pattern safe. Without it, re-running is dangerous, and the "GitHub Actions as continuous reconciler" pattern collapses. This is co-P1 with Story 1 because shipping Story 1 alone without idempotency is unsafe.

**Independent Test**: Run the workflow twice in succession on the same fleet. The second run must report `ok` (and zero `changed`) for every task in every play, and Node Exporter must not have been restarted by the second run.

**Acceptance Scenarios**:

1. **Given** Node Exporter is already installed and running at the expected version, **When** the workflow runs again, **Then** every Ansible task reports `ok` (not `changed`), and `systemctl` shows the same PID as before the run.
2. **Given** the operator has manually stopped the Node Exporter service on one instance (simulated drift), **When** the workflow runs, **Then** Ansible re-starts the service on that one instance and reports `changed` for that host only.
3. **Given** the operator has deleted the Node Exporter binary on one instance (more severe drift), **When** the workflow runs, **Then** Ansible re-downloads the binary, re-deploys the unit if needed, restarts the service, and the instance ends in the correct state.

---

### User Story 3 — Version upgrade by editing one value (Priority: P2)

As the operator, when a new Node Exporter release is available, I want to upgrade the entire fleet by changing a single version variable in the repo, committing, and letting GitHub Actions roll the change out.

**Why this priority**: Important for ongoing operability, but the feature is shippable without it as long as a manual edit + re-run achieves the upgrade. This story formalizes the contract.

**Independent Test**: Bump the version variable from `vX` to `vY` in the role's defaults, push to `main`, and observe that the workflow downloads the new binary, replaces the symlink (or binary), and restarts the service — and that the second post-upgrade run reports zero changes.

**Acceptance Scenarios**:

1. **Given** the fleet is converged on Node Exporter version `vX`, **When** the operator changes the version default to `vY` and merges to `main`, **Then** Ansible installs `vY` on every target and restarts the service.
2. **Given** the upgrade has just completed, **When** the workflow runs again on the next schedule tick, **Then** all tasks report `ok` with zero changes.

---

### User Story 4 — Scoped run with manual dispatch (Priority: P3)

As the operator, when I want to test a change against one specific instance without touching the whole fleet, I want to manually dispatch the workflow with a tag filter override (e.g., a specific `Name` tag value) and have it apply only there.

**Why this priority**: Operationally useful, but not required for the MVP. A scheduled fleet-wide reconcile + a `main` trigger covers the day-one need.

**Independent Test**: Use the GitHub Actions "Run workflow" button to dispatch with an override input that narrows the fleet to a single instance, and verify only that one instance is touched.

**Acceptance Scenarios**:

1. **Given** a fleet of three matching instances, **When** the operator dispatches the workflow with an override that narrows to one instance ID, **Then** Ansible runs against only that instance.

---

### Edge Cases

- **Target instance has no SSM Agent or no IAM instance profile.** Workflow must fail loudly on that one host with a clear error pointing at SSM connectivity, and must not silently skip it.
- **Target instance is `stopped` or `pending` when the run starts.** The dynamic inventory filter must exclude any state that isn't `running`; the run must succeed against the rest.
- **AWS API rate limits during inventory discovery.** The workflow must surface the throttling error clearly rather than producing a confusing "empty inventory" result.
- **Node Exporter download URL returns 404 (release retracted upstream).** The task must fail loudly with the URL and the configured version, not silently fall back to an older version.
- **Port 9100 is already in use on a target by an unrelated process.** Node Exporter will fail to start; the workflow must surface the `systemd` failure and report that host as failed.
- **A target host is offline / SSM session times out.** That host is reported failed, but the workflow continues against the rest and exits non-zero only if any host failed.
- **GitHub OIDC token does not grant the AWS permissions Ansible needs** (e.g., `ec2:DescribeInstances`, `ssm:StartSession`, `ssm:SendCommand`, `ssm:DescribeInstanceInformation`). Workflow must fail at the AWS credential or inventory step with an actionable error.
- **Mixed CPU architectures in the fleet (`amd64` vs `arm64`).** The role must pick the correct binary per host based on Ansible facts. If facts indicate an unsupported architecture, the run must fail clearly for that host.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST install Prometheus Node Exporter on every EC2 instance whose tags match a configurable selector. The default selector is: `Environment=dev`, `ManagedBy=ansible`, `Process=monitoring`, `version=blue`, `Owner=<current GitHub repository name>`, and `instance-state-name=running`. All five tag values plus the environment and version slot MUST be overridable via workflow inputs without editing role or inventory code.
- **FR-002**: The system MUST connect to those instances exclusively over AWS Systems Manager Session Manager. It MUST NOT require SSH, port 22, or any inbound network reachability to the instances.
- **FR-003**: The system MUST discover target instances dynamically from AWS at run time, addressing each host by its EC2 instance ID. Static inventory files MUST NOT be used as the source of truth for which hosts exist.
- **FR-004**: The system MUST run Node Exporter as a dedicated, non-login OS user (default name `node_exporter`), managed by `systemd`, listening on `0.0.0.0` TCP port 9100 by default (all interfaces). The Ansible layer MUST NOT modify any host-level firewall (`firewalld`, `ufw`, `iptables`, `nftables`); network reachability is owned by the Terragrunt-managed AWS security groups, which are expected to allow inbound `9100/tcp` from inside the VPC CIDR only.
- **FR-005**: The system MUST be idempotent: a second run against an already-converged fleet MUST report zero `changed` tasks and MUST NOT restart the service.
- **FR-006**: The system MUST be triggerable from GitHub Actions in three modes: (a) on push to `main`, (b) on manual `workflow_dispatch`, and (c) on a recurring hourly schedule.
- **FR-007**: The system MUST authenticate to AWS using the repo's existing GitHub OIDC pattern. It MUST NOT introduce static AWS access keys.
- **FR-008**: The system MUST pin the Ansible version and the AWS Ansible collection version used in CI, and MUST install the SSM session plugin required by the SSM connection on the GitHub runner.
- **FR-009**: The system MUST expose a small set of configurable values — at minimum: target AWS region, target tag selector, Node Exporter version, and listen port — and MUST keep these in role defaults / workflow inputs rather than hard-coded inside tasks.
- **FR-010**: The system MUST select the correct binary architecture per host based on Ansible-gathered facts (Linux `amd64` vs `arm64`), and MUST fail clearly for unsupported architectures rather than installing the wrong artifact.
- **FR-011**: The system MUST verify, as the final step of the run, that the Node Exporter service is `active (running)` on each successful host. A failure of that check on any host MUST cause the workflow to exit non-zero.
- **FR-012**: The system MUST integrity-check the downloaded Node Exporter artifact before installing it. Specifically, it MUST download the upstream `sha256sums.txt` published alongside the same release tag at `https://github.com/prometheus/node_exporter/releases/download/v<ver>/sha256sums.txt`, extract the entry for the platform-specific tarball, compare it to the locally computed SHA256, and refuse to install a binary whose checksum does not match. No mirror or fallback source is allowed in v1.
- **FR-013**: The system MUST surface per-host failures clearly in the workflow logs (which host, which task, what error), and MUST continue running against the other hosts when one host fails.
- **FR-017**: The system MUST apply trigger-aware failure semantics when deciding the workflow exit code. For `push` and `workflow_dispatch` triggers, ANY host failure MUST cause the workflow to exit non-zero (strict mode). For the recurring `schedule` trigger, the workflow MUST exit non-zero only if (a) any in-scope host is fully SSM-unreachable, OR (b) the share of in-scope hosts with any task failure exceeds a configurable threshold (default: 20%). Otherwise the scheduled run MUST exit zero and record per-host failures in the GitHub Actions run summary (annotations / step summary) so a human can review without the run going red. The threshold MUST be exposed as a workflow input.
- **FR-018**: The workflow MUST declare a GitHub Actions `concurrency` group keyed on environment and AWS region (e.g. `nodeexp-<environment>-<aws_region>`) with `cancel-in-progress: false`. If a second run is triggered while one is already executing for the same env+region, the second run MUST queue until the first completes and MUST NOT cancel or interrupt the in-flight run. The workflow MUST NOT introduce any target-side locking (no flock on hosts, no DynamoDB lock, no external lock store).
- **FR-014**: The system MUST keep the Ansible layer physically separate from the Terragrunt/Terraform layer in the repo (its own top-level directory), to preserve the provisioning/configuration boundary established by spec `001`.
- **FR-015**: The system MUST NOT include, install, configure, package, or reference any eBPF agent, eBPF binary, or eBPF-related kernel configuration. eBPF is out of scope for this feature.
- **FR-016**: The system MUST NOT use any naming containing `kube`, `kubeadm`, `k8s`, or `kubernetes` in files, roles, playbooks, workflow jobs, inventory groups, or tags. The repo is plain VMs.

### Key Entities

- **Monitoring Target**: An EC2 instance, identified by instance ID, that matches the configured tag selector and is reachable via AWS SSM. State of interest: SSM-connectable, Node Exporter binary present at expected version, `systemd` unit present, service active on the configured port.
- **Tag Selector**: A set of AWS tag key/value pairs (and an instance-state filter) that defines fleet membership. Default: `Environment=dev`, `ManagedBy=ansible`, `Process=monitoring`, `version=blue`, `Owner=<repo name>`. Editable in one place via workflow inputs.
- **Blue/Green Slot**: The `version` tag value (`blue` by default, `green` for the opposite slot). Used to target one slot of the fleet at a time during blue/green cutovers. Not modified by this feature — it is read only.
- **Reconcile Run**: One end-to-end execution of the GitHub Actions workflow. Outcomes: green (all hosts converged), partial (some hosts failed, others converged), red (workflow itself failed before reaching hosts). The mapping of "partial" to red vs. green depends on trigger type per FR-017 — strict for push/dispatch, threshold-based for schedule.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can take a fresh, correctly tagged EC2 instance from "running, no Node Exporter" to "Node Exporter active and exposing metrics on port 9100" by merging a single commit, with no manual intervention on the host, in under 5 minutes for a single-host fleet.
- **SC-002**: A second consecutive workflow run against an unchanged, already-converged fleet produces zero `changed` task results across all hosts.
- **SC-003**: Drift on a single host (service stopped or binary missing) is corrected automatically within one scheduled reconcile cycle (one hour, by default), without operator action.
- **SC-004**: Onboarding a new operator to "I can re-run the reconciler" requires reading no more than one short README in the new Ansible directory; no separate runbook or interactive setup steps are needed.
- **SC-005**: The same workflow scales from 1 to at least 25 target instances in `us-east-1` without configuration changes other than the tag selector, and completes a full reconcile in under 10 minutes for that fleet size.
- **SC-007**: A single broken host (e.g., SSM agent down on one of 10 instances) MUST NOT cause hourly scheduled runs to repeatedly report red. With the default 20% threshold, the scheduled workflow MUST exit green for that case while still surfacing the failed host in the run summary. The same condition on a push or manual run MUST exit red.
- **SC-006**: No SSH key material, no port-22 ingress rule, and no static AWS access key is introduced into the repo, the GitHub Actions environment, or the target instances as part of this feature.

## Assumptions

- The repo's existing GitHub-OIDC-to-AWS trust is already in place for `us-east-1` and can be reused by the new workflow. If a slightly broader IAM permission set is needed (e.g., `ssm:StartSession`, `ssm:SendCommand`, `ssm:DescribeInstanceInformation`, `ec2:DescribeInstances`), it will be added to the existing OIDC-assumable role in a small, separate change rather than as part of this spec.
- Target EC2 instances are provisioned by the existing Terragrunt/Terraform layer (under `aws/dev/.../versionmesh/`) with the SSM Agent installed, an instance profile attached that includes `AmazonSSMManagedInstanceCore`, and the expected tags applied. This feature does not change provisioning.
- Targets are Linux (Ubuntu LTS or Amazon Linux 2/2023). Windows is out of scope. Architecture is `amd64` by default but the role supports `arm64` based on facts.
- Terragrunt-managed AWS security groups attached to monitoring-target instances allow inbound `9100/tcp` from within the VPC CIDR (and only from within the VPC). This SG rule is a precondition for the metrics endpoint to be reachable by future Prometheus scrapers; it is NOT created or modified by this feature. If the rule is missing, Node Exporter will still install and run correctly, but the endpoint will not be reachable — that is acceptable and is treated as an SG/IaC concern, not an Ansible concern.
- The default fleet membership is: instances in `dev`, region `us-east-1`, tagged `Environment=dev`, `ManagedBy=ansible`, `Process=monitoring`, `version=blue`, `Owner=<this repository's name>`, with state `running`. The `Owner` value is resolved at workflow run time from the GitHub repository name (e.g. `compute-ansible-deployment`) rather than being hard-coded, so the workflow remains correct under repo rename or fork. Promoting to other environments or to the `green` slot is done by overriding workflow inputs; it is not part of this spec.
- Network egress from each target EC2 instance to `https://github.com` (specifically `github.com` and `objects.githubusercontent.com` for release-asset redirects) is permitted on TCP 443, so each host can download both the Node Exporter tarball and the `sha256sums.txt` directly from the upstream release. If egress is restricted in a future environment, mirroring the artifact to an S3 bucket in the same account is the intended path, but it is explicitly out of scope for this feature.
- The repo continues to use sub-topic branches (`003-ansible-node-exporter--<topic>`) for follow-up fixes, per learning #002.
