output "wif_provider_name" {
  description = "Full WIF provider resource name"
  value       = module.gh_oidc.provider_name
}

output "service_account_email" {
  description = "CI/CD service account email"
  value       = google_service_account.github_actions.email
}

output "service_account_name" {
  description = "CI/CD service account full name"
  value       = google_service_account.github_actions.name
}
