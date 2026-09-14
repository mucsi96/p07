module "setup_app_dashboard" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_dashboard?ref=v-88"

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
  github_token               = data.azurerm_key_vault_secret.github_token.value
  owner                      = local.owner
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  valid_email                = data.azurerm_key_vault_secret.letsencrypt_email.value
  oauth2_proxy_chart_version = local.oauth2_proxy_chart_version
  oauth2_proxy_image_version = local.oauth2_proxy_image_version
  session_redis = {
    connection_url = module.create_redis.connection_url
    password       = module.create_redis.password
  }
  gateway_parent_ref = module.setup_ingress_controller.gateway_parent_ref
  wait_for           = module.setup_ingress_controller.ingress_controller_ready
}

output "dashboard_url" {
  value = module.setup_app_dashboard.url
}
