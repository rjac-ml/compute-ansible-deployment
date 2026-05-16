# Compute-Ansible Kubeadm Onboarding

This repository is now named **compute-ansible** and is maintained under
`next-signal/compute-ansible-machines`.

This onboarding note captures the kubeadm implementation history and operating
logic from the `specs` workstream, so the context remains available even if
`specs/` is removed.

## Kubeadm Evolution (Spec-Driven Summary)

### 1) Kubeadm EC2 Lab Foundation

The first kubeadm implementation introduced a dedicated AWS lab designed for
manual Kubernetes learning:

- isolated from EKS (separate VPC and separate state key)
- 4 EC2 nodes total (2 control-plane, 2 worker)
- SSM-only access (no bastion, no SSH keys, no public IP requirement)
- kubeadm/kubelet/containerd preinstalled via user data
- no automatic cluster bootstrap (manual `kubeadm init/join` by design)

Implementation model followed the phase logic from specs:

1. create new Terraform module: `aws/terraform/modules/kubeadm`
2. create Terragrunt units for lab VPC + EC2
3. add `just` and workflow support (`kubeadm` option, `aws-ssm` recipe)
4. perform operational bootstrap manually after infra provisioning

### 2) Kubeadm DNS Enhancement

The next kubeadm-focused evolution added internal DNS requirements for more
stable control-plane and node-to-node bootstrapping:

- private hosted zone for kubeadm nodes
- A records for `cp-*` and `worker-*` instances
- hostname-based control-plane endpoint for `kubeadm init`
- lifecycle tied to kubeadm lab create/destroy

Core intent: replace fragile IP-based joins with stable internal hostnames.

## Current Kubeadm Operating Logic

- Terragrunt pathing defines environment targeting for kubeadm components.
- Kubeadm lab infra is provisioned/destroyed with the same CI/CD pattern used
  elsewhere (plan/provision/destroy), but bootstrap remains manual.
- `just` is the canonical operator interface for kubeadm workflows.
- Generated `.terragrunt-cache` content is ephemeral and not source of truth.

## Practical Flow for Engineers

1. Provision kubeadm infra (VPC + EC2 nodes).
2. Connect to nodes through SSM.
3. Run `kubeadm init` on the first control-plane node.
4. Join remaining control-plane/worker nodes using join commands.
5. Verify with `kubectl get nodes`.
6. Destroy lab when done to control costs.

## Naming and Consistency Rules

- Project name: **compute-ansible**
- GitHub org/repo identity: `next-signal/compute-ansible-machines`
- Keep new kubeadm changes aligned with compute-ansible naming and current `just`
  workflow conventions.
