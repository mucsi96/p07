# Application-owned infrastructure; reusable modules remain pinned to v-101.

locals {
  hello_app_hostname = "hello.${data.azurerm_key_vault_secret.dns_zone.value}"
}

module "hello_postgres_schema" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_postgres_schema?ref=v-101"

  database = local.database
  schema   = "hello"
}

module "hello_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-101"

  github_repository = "skeleton-app"
  environment_name  = var.environment_name
  app_name          = "hello"
  app_secrets = {
    claude-api-key = sensitive(data.azurerm_key_vault_secret.hello_claude_api_key.value)
  }
  deployment_secrets = {
    client-storage-config = jsonencode(module.hello_client_storage.deployment_config)
    forward-auth-config   = jsonencode(module.hello_forward_auth.deployment_config)
  }
  azure_location         = var.azure_location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id  = var.azure_subscription_id
  owner                  = local.owner
  twingate_service_key   = sensitive(module.setup_twingate_access.service_key)
  app_hostname           = local.hello_app_hostname
  api_client_id          = module.setup_hello_api.client_id
  api_client_secret      = module.setup_hello_api.client_secret
  spa_client_id          = module.setup_hello_web.client_id
  api_resource_object_id = module.setup_hello_api.resource_object_id
  k8s_oidc_config        = sensitive(module.setup_cluster.k8s_oidc_config)
  client_log_url         = "https://${local.hello_hostname}${module.setup_victoria_logs.faro_client_path}"
}

module "hello_client_storage" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_static_website?ref=v-101"

  name                = "${var.environment_name}helloweb${substr(sha256(var.azure_subscription_id), 0, 8)}"
  resource_group_name = var.environment_name
  location            = var.azure_location
  deploy_principal_id = module.hello_app_base.deploy_principal_id
  app_origin          = "https://${local.hello_app_hostname}"
}

module "setup_hello_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-101"
  owner  = local.owner

  display_name = "Hello API"
  roles        = ["readGreetings", "createGreeting"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "hello"
  k8s_service_account_name      = "hello-api-workload-identity"
}

module "setup_hello_web" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_web?ref=v-101"
  owner  = local.owner

  display_name  = "Hello Web"
  redirect_uris = ["https://${local.hello_app_hostname}/oauth2/callback"]
  api_access = {
    application_id = module.setup_hello_api.application_id
    client_id      = module.setup_hello_api.client_id
    scope_id       = module.setup_hello_api.scope_id
  }
}

module "hello_forward_auth" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_forwardauth?ref=v-101"

  name                = "hello"
  namespace           = module.hello_app_base.namespace
  hostname            = local.hello_app_hostname
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client_id           = module.setup_hello_web.client_id
  client_secret       = module.setup_hello_web.client_secret
  api_client_id       = module.setup_hello_api.client_id
  trusted_proxy_cidrs = nonsensitive(sensitive(local.app_forward_auth).trusted_proxy_cidrs)
  session_redis       = sensitive(local.app_forward_auth).session_redis
  gateway_parent_ref  = sensitive(local.app_forward_auth).gateway_parent_ref
}

resource "kubernetes_persistent_volume_v1" "hello_app_pv" {
  metadata {
    name = "hello-app"
  }

  spec {
    storage_class_name = ""
    access_modes       = ["ReadWriteOnce"]
    capacity = {
      storage = "5Gi"
    }
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      host_path {
        path = "/data/hello"
      }
    }
  }
}

resource "kubernetes_persistent_volume_v1" "hello_backup_pv" {
  metadata {
    name = "hello-backup"
  }

  spec {
    storage_class_name = ""
    access_modes       = ["ReadWriteOnce"]
    capacity = {
      storage = "5Gi"
    }
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      host_path {
        path = "/data/hello"
      }
    }
  }
}

resource "azurerm_key_vault_secret" "hello_db_url" {
  key_vault_id = module.hello_app_base.key_vault_id
  name         = "db-url"
  value        = module.hello_postgres_schema.jdbc_url
}

resource "azurerm_key_vault_secret" "hello_db_username" {
  key_vault_id = module.hello_app_base.key_vault_id
  name         = "db-username"
  value        = module.hello_postgres_schema.credentials.username
}

resource "azurerm_key_vault_secret" "hello_db_password" {
  key_vault_id = module.hello_app_base.key_vault_id
  name         = "db-password"
  value        = module.hello_postgres_schema.credentials.password
}
