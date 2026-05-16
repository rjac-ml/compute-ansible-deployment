output "client_id" {
  description = "Application (Client) ID of the App Registration"
  value       = data.azuread_application.github_actions.client_id
}

output "principal_id" {
  description = "Object ID of the Service Principal"
  value       = data.azuread_service_principal.github_actions.object_id
}

output "app_display_name" {
  description = "Display name of the App Registration"
  value       = data.azuread_application.github_actions.display_name
}
