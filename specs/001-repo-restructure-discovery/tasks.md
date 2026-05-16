# Tasks: Repository Restructure & VM Service Discovery

**Input**: Design documents from `specs/001-repo-restructure-discovery/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Terraform modules: `aws/terraform/modules/<name>/`
- Terragrunt configs: `aws/<account>/<region>/<versionmesh>/<component>/terragrunt.hcl`
- Account config: `aws/<account>/account.hcl`
- Region config: `aws/<account>/<region>/region.hcl`

---

## Phase 1: Setup (Delete Old Layout)

**Purpose**: Remove the old directory structure to start clean

- [x] T001 Delete the old AWS directory tree at `aws/us-east-1/` (the entire `us-east-1/compute-ansible/` structure including `shared/oidc/`, `dev/kubeadm/vpc/`, `dev/kubeadm/ec2/`). Old S3 state keys in `compute-ansible-tg-state-dev` (e.g., `us-east-1/compute-ansible/dev/kubeadm/*/terraform.tfstate`) are intentionally abandoned — do NOT delete S3 objects (they serve as forensic record of prior deployments and cost nothing to retain)

**Checkpoint**: Old layout removed. New layout can be created.

---

## Phase 2: Foundational (Root Config + Account Structure)

**Purpose**: Set up the new account-first directory convention and update root.hcl path parsing. MUST complete before any user story work.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 Create `aws/dev/account.hcl` with locals: `account = "dev"`, `account_id = "317374277503"`, `profile = "devops-compute-ansible"`
- [x] T003 Create `aws/dev/us-east-1/region.hcl` with locals: `region = "us-east-1"` (simplified — account_id and profile moved to account.hcl)
- [x] T004 Update `aws/root.hcl` to parse the new path pattern: change `path_parts` indices (`environment` → `path_parts[0]` renamed to `account`, `region` → `path_parts[1]`, `cluster_color` → `path_parts[2]` renamed to `versionmesh`), load `account.hcl` via `find_in_parent_folders`, handle `shared` case where `path_parts[1] == "shared"` (no region/versionmesh), rename `ClusterColor` tag to `Versionmesh` in `default_tags`, rename common input `cluster_color` to `versionmesh` and `environment` to `account`

**Checkpoint**: Foundation ready — `root.hcl` correctly parses `aws/dev/us-east-1/bluemesh/` and `aws/dev/shared/oidc/` paths.

---

## Phase 3: User Story 1 - Restructure Repository Layout (Priority: P1)

**Goal**: Create the new `aws/dev/us-east-1/bluemesh/` directory structure with terragrunt.hcl files for vpc and ec2 components, plus the shared/oidc unit.

**Independent Test**: `terragrunt validate` from each unit in the new layout succeeds with correct provider and state configuration derived from the path.

### Implementation for User Story 1

- [x] T005 [US1] Create `aws/dev/shared/oidc/terragrunt.hcl` — copy from old `aws/us-east-1/compute-ansible/shared/oidc/terragrunt.hcl`, update `include.root.locals` references from `environment` to `account` and `cluster_color` to `versionmesh` where applicable
- [x] T006 [P] [US1] Create `aws/dev/us-east-1/bluemesh/vpc/terragrunt.hcl` — copy from old `aws/us-east-1/compute-ansible/dev/kubeadm/vpc/terragrunt.hcl`, update `include.root.locals` references (`environment` → `account`, `cluster_color` → `versionmesh`), set `name` input to use versionmesh
- [x] T007 [P] [US1] Create `aws/dev/us-east-1/bluemesh/ec2/terragrunt.hcl` — copy from old `aws/us-east-1/compute-ansible/dev/kubeadm/ec2/terragrunt.hcl`, update `include.root.locals` references, add `deployment_code` input as `"${include.root.locals.versionmesh}-${include.root.locals.account}-${include.root.locals.region}"`
- [x] T008 [US1] Validate the new layout: run `just validate` to confirm all modules pass syntax validation, then verify `root.hcl` path parsing by inspecting `terragrunt render-json` output from `aws/dev/us-east-1/bluemesh/vpc/` and `aws/dev/shared/oidc/`

**Checkpoint**: US1 complete — new directory layout is in place, terragrunt validates cleanly from new paths.

---

## Phase 4: User Story 2 - EC2 Service Discovery (Priority: P2)

**Goal**: Add `deployment_code` tag, IAM permissions, IMDS instance tags, and peer discovery to the kubeadm module so instances can find each other.

**Independent Test**: After deploy, run `aws ec2 describe-instances --filters "Name=tag:deployment_code,Values=bluemesh-dev-us-east-1"` and verify all instances are returned.

### Implementation for User Story 2

- [x] T009 [P] [US2] Add `deployment_code` variable to `aws/terraform/modules/kubeadm/variables.tf` — type string, description "Unique deployment identifier for tag-based service discovery (format: versionmesh-account-region)"
- [x] T010 [P] [US2] Add `deployment_code` tag to `aws_instance.control_plane` and `aws_spot_instance_request.worker` in `aws/terraform/modules/kubeadm/main.tf`
- [x] T011 [US2] Add `aws_ec2_tag.worker_deployment_code` resource in `aws/terraform/modules/kubeadm/main.tf` to propagate `deployment_code` tag to spot instances (same pattern as existing `aws_ec2_tag.worker_name`, `aws_ec2_tag.worker_role`, etc.)
- [x] T012 [US2] Add `aws_iam_role_policy.ec2_discovery` inline policy to the SSM role in `aws/terraform/modules/kubeadm/main.tf` granting `ec2:DescribeInstances` and `ec2:DescribeTags` with `Resource = "*"`
- [x] T013 [US2] Add `metadata_options` block to both `aws_instance.control_plane` and `aws_spot_instance_request.worker` in `aws/terraform/modules/kubeadm/main.tf`: `http_endpoint = "enabled"`, `http_tokens = "required"`, `instance_metadata_tags = "enabled"`
- [x] T014 [US2] Update `aws/terraform/modules/kubeadm/user-data.sh` — replace `aws ec2 describe-tags` hostname code (lines 59-70) with IMDS tag read (`curl http://169.254.169.254/latest/meta-data/tags/instance/Name`), add peer discovery section that reads `deployment_code` from IMDS, queries `ec2:DescribeInstances` with filter, writes results to `/etc/compute-ansible/peers.json` (JSON schema: `[{"name": "cp-1", "ip": "10.0.1.5", "role": "control-plane"}]`), includes retry loop (max 10 retries, 5s backoff), writes empty array if no peers found after retries
- [x] T015 [US2] Add `deployment_code` output to `aws/terraform/modules/kubeadm/outputs.tf`
- [x] T016 [US2] Run `just fmt` and `just validate` to confirm all module changes are syntactically valid

**Checkpoint**: US2 complete — kubeadm module has deployment_code tagging, IAM discovery permissions, IMDS tags, and user-data peer discovery.

---

## Phase 5: User Story 3 - Update CI/CD & Justfile (Priority: P3)

**Goal**: Update the justfile and GitHub Actions workflows to work with the new `<provider>/<account>/<region>/<versionmesh>` directory layout.

**Independent Test**: `just aws-plan dev us-east-1 bluemesh` resolves to the correct directory path. GitHub Actions workflow inputs accept account/region/versionmesh.

### Implementation for User Story 3

- [x] T017 [P] [US3] Update `justfile` — change `aws_dir` to remove hardcoded region, add `region` parameter to all AWS recipes (`aws-plan account region versionmesh`, `aws-apply account region versionmesh`, etc.), update `aws-apply-shared` and `aws-plan-shared` to use `aws/{{account}}/shared` path, update `aws-ssm` recipe for new path, update `aws-init` recipe, keep GCP recipes unchanged for now
- [x] T018 [P] [US3] Update `.github/workflows/aws-kubernetes-plan.yaml` — rename `environment` input to `account`, update `cluster` options to include `bluemesh`, add `${{ env.REGION }}` parameter to `just` calls (`just aws-init ${{ env.ACCOUNT }} ${{ env.REGION }} ${{ env.CLUSTER }}`), update concurrency group key
- [x] T019 [P] [US3] Update `.github/workflows/aws-kubernetes-provision.yaml` — same changes as T018 (rename environment→account, update cluster options, add region to just calls)
- [x] T020 [P] [US3] Update `.github/workflows/aws-kubernetes-destroy.yaml` — same changes as T018
- [x] T021 [US3] Update `bin/aws-connect.sh` — update to accept account/versionmesh args instead of environment/color, update cluster name construction to `compute-ansible-${ACCOUNT}-${VERSIONMESH}`, update role name construction

**Checkpoint**: US3 complete — justfile and CI/CD workflows target the new directory layout.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation updates

- [x] T022 [P] Update `CLAUDE.md` — update directory-as-contract section to reflect new `<provider>/<account>/<region>/<versionmesh>` pattern, update command examples to use new justfile signatures, update module layout section
- [x] T023 [P] Update `README.md` — update repository structure diagram, deployment examples, and cluster access commands to reflect new layout
- [x] T024 [P] Update `GUIDE.md` — update repository layout section, just command reference, and all deployment examples to use new path pattern and recipe signatures
- [x] T025 Amend `.specify/memory/constitution.md` — update Principle III directory-as-contract pattern from `<provider>/<region>/compute-ansible/<env>/<color>` to `<provider>/<account>/<region>/<versionmesh>`, bump version to 1.1.0
- [x] T026 Run full validation: `just fmt`, `just validate`, `just check-rename`, verify `terragrunt render-json` from `aws/dev/us-east-1/bluemesh/vpc/` shows correct provider config

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (old tree deleted before new config created)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (root.hcl + account.hcl must exist)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (ec2/terragrunt.hcl must exist to pass deployment_code input)
- **User Story 3 (Phase 5)**: Depends on Phase 3 (new directory paths must exist for justfile/workflows to reference)
- **Polish (Phase 6)**: Depends on Phases 3, 4, and 5

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational only — creates the directory structure
- **User Story 2 (P2)**: Depends on US1 — needs ec2/terragrunt.hcl to exist for deployment_code input wiring
- **User Story 3 (P3)**: Depends on US1 — needs new directory paths to exist. Can run in parallel with US2

### Within Each User Story

- Tasks marked [P] can run in parallel (different files)
- T008 (validation) must run after T005-T007
- T016 (validation) must run after T009-T015
- T021 depends on T017 (justfile must be updated before connect script references new patterns)

### Parallel Opportunities

- T006 + T007 can run in parallel (different terragrunt.hcl files)
- T009 + T010 can run in parallel (variables.tf vs main.tf)
- T017 + T018 + T019 + T020 can all run in parallel (different files)
- T022 + T023 + T024 can run in parallel (different docs)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Delete old layout
2. Complete Phase 2: Root config + account structure
3. Complete Phase 3: US1 — new directory layout
4. **STOP and VALIDATE**: `terragrunt validate` from new paths
5. This is deployable as-is (directory restructure without discovery)

### Incremental Delivery

1. Phases 1-3 → Directory restructure validated → commit
2. Phase 4 → Service discovery added → commit
3. Phase 5 → CI/CD updated → commit
4. Phase 6 → Docs + constitution amended → commit + PR

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- This is a greenfield implementation — no state migration, no backward compatibility with old layout
- GCP restructure is explicitly out of scope (separate spec)
- Avoid: modifying GCP root.hcl or GCP workflows in this spec
