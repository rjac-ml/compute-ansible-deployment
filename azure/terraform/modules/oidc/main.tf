# GitHub Actions OIDC — references pre-existing App Registration
# The App Registration and Federated Credential are created via CLI (see guide/azure/03-oidc-federation.md)

data "azuread_application" "github_actions" {
  display_name = var.app_display_name
}

data "azuread_service_principal" "github_actions" {
  client_id = data.azuread_application.github_actions.client_id
}

resource "azurerm_role_assignment" "contributor" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.github_actions.object_id
}
