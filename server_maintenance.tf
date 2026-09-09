moved {
  from = azuread_application.server_maintenance
  to   = module.setup_cluster.azuread_application.server_maintenance
}

moved {
  from = azuread_service_principal.server_maintenance
  to   = module.setup_cluster.azuread_service_principal.server_maintenance
}

moved {
  from = azuread_application_federated_identity_credential.server_maintenance
  to   = module.setup_cluster.azuread_application_federated_identity_credential.server_maintenance
}

moved {
  from = azurerm_role_assignment.server_maintenance_secret_reader
  to   = module.setup_cluster.azurerm_role_assignment.server_maintenance_secret_reader
}

moved {
  from = github_actions_secret.server_maintenance_twingate_service_key
  to   = module.setup_cluster.github_actions_secret.server_maintenance_twingate_service_key
}

moved {
  from = github_actions_secret.server_maintenance_azure_client_id
  to   = module.setup_cluster.github_actions_secret.server_maintenance_azure_client_id
}

moved {
  from = github_actions_secret.server_maintenance_azure_tenant_id
  to   = module.setup_cluster.github_actions_secret.server_maintenance_azure_tenant_id
}

moved {
  from = github_actions_secret.server_maintenance_azure_subscription_id
  to   = module.setup_cluster.github_actions_secret.server_maintenance_azure_subscription_id
}

moved {
  from = github_actions_secret.server_maintenance_azure_keyvault_name
  to   = module.setup_cluster.github_actions_secret.server_maintenance_azure_keyvault_name
}
