---
name: no-kubernetes-references
description: Never use kubernetes/kubeadm naming in this repo — it's plain VM infrastructure
type: feedback
---

This repo deploys plain VMs, not Kubernetes. Never use "kubernetes", "kubeadm", "kube", "k8s" in resource names, workflow names, job IDs, module names, or tags. Use "infra" instead.

**Why:** The repo was originally built for kubeadm clusters but pivoted to generic EC2/VM deployments. Multiple rounds of cleanup were needed to remove kubernetes references from workflows, modules, and tags.

**How to apply:** When creating new workflows, modules, or resources, use "infra" naming (e.g., `aws-infra-plan`, `infra-provision`). Grep for "kube" before any PR.
