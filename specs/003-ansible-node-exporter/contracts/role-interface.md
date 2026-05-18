# Contract: `roles/node_exporter` Role Interface

This is the public surface of the role — what callers may set and what the role guarantees in return. Internal task split is implementation detail and may change.

## Inputs (callers may override)

All variables live in `roles/node_exporter/defaults/main.yml`. Any can be overridden by:

- The playbook (`vars:` on the play)
- Workflow env → playbook `vars` (the conventional path in CI)
- Host vars (rare; supported)

| Variable | Type | Default | Override safety |
| --- | --- | --- | --- |
| `node_exporter_version` | string | `"1.10.2"` | Safe; triggers download + restart on change |
| `node_exporter_user` | string | `"node_exporter"` | Safe but creates a new user; old user is NOT cleaned up |
| `node_exporter_port` | int | `9100` | Safe; triggers unit re-template + restart |
| `node_exporter_bind_address` | string | `"0.0.0.0"` | Per Q1 clarification; downstream SG must match |
| `node_exporter_install_dir` | string | `"/opt/node_exporter"` | Changing this orphans prior installs |
| `node_exporter_bin_path` | string | `"/usr/local/bin/node_exporter"` | Symlink target |
| `node_exporter_arch_map` | dict | `{x86_64: amd64, aarch64: arm64}` | Add entries for new arches |
| `node_exporter_disabled_collectors` | list | `[]` | Empty in v1 per spec |
| `node_exporter_enabled_collectors` | list | `[]` | Empty in v1 per spec |

## Guarantees on successful completion

- A system user named `{{ node_exporter_user }}` exists with `/usr/sbin/nologin`.
- The binary `node_exporter-{{ version }}.linux-{{ arch }}` is present under `{{ install_dir }}/{{ version }}/` and its SHA256 matches `sha256sums.txt` from the upstream release.
- `{{ bin_path }}` is a symlink pointing at the active version's binary.
- `/etc/systemd/system/node_exporter.service` exists, owned `root:root`, mode `0644`, and templates from `templates/node_exporter.service.j2`.
- `systemctl is-enabled node_exporter` returns `enabled`.
- `systemctl is-active node_exporter` returns `active`.
- `curl -fsS http://127.0.0.1:{{ port }}/metrics` returns HTTP 200 and a payload starting with `# HELP`.

## Idempotency contract

- Re-running the role with unchanged inputs MUST produce zero `changed` tasks.
- `daemon-reload` and `restart node_exporter` handlers fire ONLY when the unit file content, binary path, or binary checksum changes.
- Downloads use `creates:` predicates to skip when the destination is already present and intact.

## Failure modes (role-level)

| Condition | Result |
| --- | --- |
| `ansible_system != Linux` | Task `preflight.yml` fails the host with a clear message; play continues against other hosts. |
| `ansible_architecture` not in `node_exporter_arch_map` | Same as above. |
| Tarball download HTTP error | `get_url` fails; play continues against other hosts. |
| Tarball checksum mismatch | `get_url` reports a mismatch; binary is NOT installed; host fails. |
| `systemd` unit start fails | `systemd` module fails; verify step does not run on that host; host fails. |
| Verify step `/metrics` returns non-200 | `uri` module fails; host fails. |

## Caller-side contract (playbook responsibilities)

- Use `become: true` (the role's tasks assume root).
- Use `gather_facts: true` (preflight needs facts).
- Apply the role to a host group derived from the dynamic inventory's `keyed_groups` (e.g. `versionmesh_bluemesh`).
