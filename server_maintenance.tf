locals {
  server_maintenance_repository = "p07"
  server_maintenance_secret_scopes = {
    host            = azurerm_key_vault_secret.host.resource_versionless_id
    ssh_port        = azurerm_key_vault_secret.ssh_port.resource_versionless_id
    ssh_private_key = azurerm_key_vault_secret.ssh_private_key.resource_versionless_id
    ssh_user_name   = azurerm_key_vault_secret.ssh_user_name.resource_versionless_id
  }
}

resource "azuread_application" "server_maintenance" {
  display_name     = "GitHub Actions server maintenance - ${var.environment_name}"
  sign_in_audience = "AzureADMyOrg"
  owners           = [local.owner]
}

resource "azuread_service_principal" "server_maintenance" {
  client_id = azuread_application.server_maintenance.client_id
  owners    = [local.owner]
}

resource "azuread_application_federated_identity_credential" "server_maintenance" {
  application_id = azuread_application.server_maintenance.id
  display_name   = "github-actions-server-maintenance"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:mucsi96/${local.server_maintenance_repository}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "server_maintenance_secret_reader" {
  for_each = local.server_maintenance_secret_scopes

  scope                = each.value
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.server_maintenance.object_id
}

resource "github_actions_secret" "server_maintenance_twingate_service_key" {
  repository  = local.server_maintenance_repository
  secret_name = "TWINGATE_SERVICE_KEY"
  value       = module.setup_twingate_access.service_key
}

resource "github_actions_secret" "server_maintenance_azure_client_id" {
  repository  = local.server_maintenance_repository
  secret_name = "AZURE_CLIENT_ID"
  value       = azuread_application.server_maintenance.client_id
}

resource "github_actions_secret" "server_maintenance_azure_tenant_id" {
  repository  = local.server_maintenance_repository
  secret_name = "AZURE_TENANT_ID"
  value       = var.azure_tenant_id
}

resource "github_actions_secret" "server_maintenance_azure_subscription_id" {
  repository  = local.server_maintenance_repository
  secret_name = "AZURE_SUBSCRIPTION_ID"
  value       = var.azure_subscription_id
}

resource "github_actions_secret" "server_maintenance_azure_keyvault_name" {
  repository  = local.server_maintenance_repository
  secret_name = "AZURE_KEYVAULT_NAME"
  value       = data.azurerm_key_vault.kv.name
}
