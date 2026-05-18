# Quickstart: Ansible Node Exporter

**Feature**: `003-ansible-node-exporter` · **Date**: 2026-05-17

Audience: an operator on their workstation, with the repo cloned. Goal: go from "fresh clone" to "Node Exporter running on the bluemesh dev fleet" in under 5 minutes (matches SC-001).

> Constitutional note (Principle II — git-driven deployment): the supported production path is **push to `main` → GitHub Actions**. The local recipes below are for *plan / dry-run / emergency reconcile only*. They never apply changes by default.

---

## Prerequisites (one-time, local)

```bash
# 1. AWS CLI v2 + Session Manager plugin
aws --version            # expect: aws-cli/2.x
session-manager-plugin --version

# 2. just + python 3.12
just --version
python --version

# 3. Authenticated AWS session that can read EC2 + SSM
#    (e.g. SSO profile that maps to the OIDC role, or a sandbox role)
aws sts get-caller-identity
```

## Step 1 — install Ansible deps

```bash
just ansible-setup
```

This runs `pip install -r ansible/requirements.txt` and `ansible-galaxy collection install -r ansible/requirements.yml`. Idempotent.

## Step 2 — list discovered targets (read-only)

```bash
just ansible-inventory dev us-east-1 bluemesh
```

Expected: one entry per running EC2 instance under the `bluemesh` slot in `us-east-1`, hostnames being `i-...` instance IDs, every host bound to `ansible_connection=aws_ssm`. Zero hosts is a valid result and means the fleet is currently empty — not a failure.

## Step 3 — dry-run (check + diff)

```bash
just ansible-plan dev us-east-1 bluemesh
```

This runs `ansible-playbook --check --diff` over SSM. Every task reports `ok` or `changed (check mode)`; nothing is actually modified on the hosts. Use this to preview a version bump before merging.

## Step 4 — verify what's already installed (one host)

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=compute-ansible" \
            "Name=tag:Account,Values=dev" \
            "Name=tag:Versionmesh,Values=bluemesh" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text | head -1)

aws ssm start-session --target "$INSTANCE_ID" \
  --document-name AWS-StartNonInteractiveCommand \
  --parameters 'command=["systemctl is-active node_exporter && curl -fsS http://127.0.0.1:9100/metrics | head -3"]'
```

Expected on a converged host:

```text
active
# HELP go_gc_duration_seconds A summary of the wall-time pause ...
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 0.0001
```

## Step 5 — make a real change

```bash
# Bump the default version in roles/node_exporter/defaults/main.yml
sed -i 's/node_exporter_version: ".*"/node_exporter_version: "1.10.2"/' \
  ansible/roles/node_exporter/defaults/main.yml

git checkout -b 003-ansible-node-exporter--bump-1.10.2
git commit -am "bump node_exporter to 1.10.2"
git push -u origin HEAD
# open PR; CI runs ansible-plan; merge → CI runs ansible-apply
```

## Step 6 — observe a real run

GitHub → Actions → "Ansible Node Exporter" workflow. Each run produces a step summary with:

- Total targeted hosts
- Per-host `ok / changed / failed / unreachable` counts
- Final exit-code decision (strict vs threshold)

On the hourly schedule, a converged fleet shows all-zero `changed`. Drift (e.g. a host where someone killed the service) shows `1 changed` for that host only, and the run goes green.

---

## Emergency reconcile (local apply)

Only when CI is broken AND drift must be corrected immediately:

```bash
just ansible-apply dev us-east-1 bluemesh
```

Document the reason in `#ops` channel; this bypasses the PR review trail and should be rare.

---

## Acceptance tests (manual, for the implementer)

These map to the spec's `Acceptance Scenarios`:

| Test | Command | Expected |
| --- | --- | --- |
| Story 1, Scenario 1 | merge PR → wait for workflow | green, `node_exporter` active on every host |
| Story 1, Scenario 2 | `curl :9100/metrics` from inside VPC | `200 OK`, `node_*` series present |
| Story 1, Scenario 3 | change `Versionmesh` filter to `nonexistent` and dispatch | green, "no targets matched" in summary |
| Story 2, Scenario 1 | run workflow twice | second run has `changed=0` everywhere |
| Story 2, Scenario 2 | `systemctl stop node_exporter` on one host, dispatch | only that host shows `changed`, service restarted |
| Story 2, Scenario 3 | `rm /usr/local/bin/node_exporter` on one host, dispatch | binary re-downloaded, service restarted |
| Story 3 | bump `node_exporter_version` defaults | new version installed, restart on every host; next run zero-changed |
| Edge case (SSM down) | stop SSM agent on one host, dispatch | host marked unreachable; run fails regardless of trigger (FR-017) |
| Edge case (no SG rule) | apply role on a host whose SG blocks 9100 | role still succeeds (verify uses 127.0.0.1); SG concern is out of scope |
