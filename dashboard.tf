module "setup_app_dashboard" {
  # Pin the direct-JWT/Helm module revision; v-88 still provisions the proxy.
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_dashboard?ref=b7bb0cd8ed82e1896bf3a309f8a5f587b2cd2cae"

  environment_name        = var.environment_name
  hostname                = "apps.${data.azurerm_key_vault_secret.dns_zone.value}"
  github_repository       = "observatory-app"
  github_repository_owner = "mucsi96"
  azure_subscription_id   = var.azure_subscription_id
  kubeconfig_secret_id    = azurerm_key_vault_secret.k8s_oidc_config.resource_versionless_id
  twingate_service_key    = module.setup_twingate_access.service_key
  apps = [
    module.setup_hello_app.dashboard_app,
    module.setup_learn_language_app.dashboard_app,
    module.setup_training_log_app.dashboard_app,
    module.setup_expense_tracker_app.dashboard_app,
    module.setup_library_app.dashboard_app,
    module.setup_cooking_app.dashboard_app,
    module.setup_backup_app.dashboard_app,
  ]
  github_token                 = data.azurerm_key_vault_secret.github_token.value
  owner                        = local.owner
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  database                     = local.database
  client_log_url               = local.client_log_url
  k8s_oidc_issuer_url          = module.setup_cluster.oidc_issuer_url
  ingress_controller_namespace = module.setup_ingress_controller.ingress_controller_namespace
  wait_for                     = module.setup_ingress_controller.ingress_controller_ready
}

output "dashboard_url" {
  value = module.setup_app_dashboard.url
}
