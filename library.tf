# Application-owned infrastructure; reusable modules remain pinned to v-102.

locals {
  library_app_hostname = "library.${data.azurerm_key_vault_secret.dns_zone.value}"
}

module "library_postgres_schema" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_postgres_schema?ref=v-104"

  database = local.database
  schema   = "library"
}

module "library_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-104"

  github_repository = "library-app"
  environment_name  = var.environment_name
  app_name          = "library"
  app_secrets = {
    openai-api-key = sensitive(data.azurerm_key_vault_secret.library_openai_api_key.value)
  }
  deployment_secrets = {
    client-storage-config = jsonencode(module.library_client_storage.deployment_config)
    forward-auth-config   = jsonencode(module.library_forward_auth.deployment_config)
  }
  azure_location         = var.azure_location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id  = var.azure_subscription_id
  owner                  = local.owner
  twingate_service_key   = sensitive(module.setup_twingate_access.service_key)
  app_hostname           = local.library_app_hostname
  api_client_id          = module.setup_library_api.client_id
  api_client_secret      = module.setup_library_api.client_secret
  spa_client_id          = module.setup_library_spa.client_id
  api_resource_object_id = module.setup_library_api.resource_object_id
  k8s_oidc_config        = sensitive(module.setup_cluster.k8s_oidc_config)
  client_log_url         = "https://${local.library_app_hostname}${module.setup_victoria_logs.faro_client_path}"
}

module "library_client_storage" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_static_website?ref=v-104"

  name                = "${var.environment_name}libweb${substr(sha256(var.azure_subscription_id), 0, 8)}"
  resource_group_name = var.environment_name
  location            = var.azure_location
  deploy_principal_id = module.library_app_base.deploy_principal_id
  app_origin          = "https://${local.library_app_hostname}"
}

module "setup_library_web" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_web?ref=v-104"
  owner  = local.owner

  display_name  = "Library Web"
  redirect_uris = ["https://${local.library_app_hostname}/oauth2/callback"]
  api_access = {
    application_id = module.setup_library_api.application_id
    client_id      = module.setup_library_api.client_id
    scope_id       = module.setup_library_api.scope_id
  }
}

module "library_forward_auth" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_forwardauth?ref=v-104"

  name                = "library"
  namespace           = module.library_app_base.namespace
  hostname            = local.library_app_hostname
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client_id           = module.setup_library_web.client_id
  client_secret       = module.setup_library_web.client_secret
  api_client_id       = module.setup_library_api.client_id
  trusted_proxy_cidrs = nonsensitive(sensitive(local.app_forward_auth).trusted_proxy_cidrs)
  session_redis       = sensitive(local.app_forward_auth).session_redis
  gateway_parent_ref  = sensitive(local.app_forward_auth).gateway_parent_ref
}

module "setup_library_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-104"
  owner  = local.owner

  display_name = "Library API"
  roles        = ["readItems", "writeItems"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "library"
  k8s_service_account_name      = "library-api-workload-identity"
}

module "setup_library_spa" {
  # Retained until the gateway app rollout is verified, so the currently
  # deployed SPA can still sign in during infrastructure provisioning.
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_spa?ref=v-104"
  owner  = local.owner

  display_name  = "Library SPA"
  redirect_uris = ["https://${local.library_app_hostname}/", "http://localhost:4250/"]

  api_id        = module.setup_library_api.application_id
  api_client_id = module.setup_library_api.client_id
  api_scope_id  = module.setup_library_api.scope_id
}

resource "kubernetes_persistent_volume_v1" "library_app_pv" {
  metadata {
    name = "library-app"
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
        path = "/data/library"
      }
    }
  }
}

resource "kubernetes_persistent_volume_v1" "library_backup_pv" {
  metadata {
    name = "library-backup"
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
        path = "/data/library"
      }
    }
  }
}

resource "azurerm_key_vault_secret" "library_db_url" {
  key_vault_id = module.library_app_base.key_vault_id
  name         = "db-url"
  value        = module.library_postgres_schema.jdbc_url
}

resource "azurerm_key_vault_secret" "library_db_username" {
  key_vault_id = module.library_app_base.key_vault_id
  name         = "db-username"
  value        = module.library_postgres_schema.credentials.username
}

resource "azurerm_key_vault_secret" "library_db_password" {
  key_vault_id = module.library_app_base.key_vault_id
  name         = "db-password"
  value        = module.library_postgres_schema.credentials.password
}
