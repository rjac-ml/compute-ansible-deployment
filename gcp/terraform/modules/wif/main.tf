# Workload Identity Federation for GitHub Actions
# Allows GitHub Actions to authenticate with GCP without long-lived credentials

locals {
  pool_id     = "github-actions-pool"
  provider_id = "github-actions-provider"
}

# WIF pool + OIDC provider via Google community module
module "gh_oidc" {
  source  = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  version = "~> 5.1"

  project_id  = var.project_id
  pool_id     = local.pool_id
  provider_id = local.provider_id

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_org}' && assertion.repository.startsWith('${var.github_org}/${var.github_repo_prefix}')"

  sa_mapping = {
    (var.service_account_id) = {
      sa_name   = google_service_account.github_actions.id
      attribute = "attribute.repository/${var.github_org}/${var.github_repo_prefix}-*"
    }
  }
}

# CI/CD service account for GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = var.service_account_id
  display_name = "GitHub Actions CI/CD"
  description  = "Service account for GitHub Actions infrastructure provisioning"
  project      = var.project_id
}

# IAM bindings for infrastructure provisioning
resource "google_project_iam_member" "container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "iam_service_account_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "service_account_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Custom role: minimal IAM policy management for GKE node SA bindings
# Replaces roles/resourcemanager.projectIamAdmin which grants broader permissions
# including project deletion protection, org policy reads, etc.
resource "google_project_iam_custom_role" "iam_binding_manager" {
  role_id     = "cicdIamBindingManager"
  title       = "CI/CD IAM Binding Manager"
  description = "Allows managing project IAM bindings (required by GKE module for node SA roles)"
  project     = var.project_id
  permissions = [
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.setIamPolicy",
  ]
}

resource "google_project_iam_member" "iam_binding_manager" {
  project = var.project_id
  role    = google_project_iam_custom_role.iam_binding_manager.id
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Explicit WIF → Service Account impersonation binding
# Ensures federated identities from the WIF pool can generate
# access tokens (iam.serviceAccounts.getAccessToken) for this SA.
#
# Uses /* (all pool identities) because GCP principalSet does NOT support
# wildcards in attribute values. Security is enforced at the pool level via
# attribute_condition which restricts token issuance to repos matching
# pixemilar/pixemilar* — so /* here is safe.
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${local.pool_id}/*"
}

