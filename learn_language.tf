# Application-owned infrastructure; reusable modules remain pinned to v-102.

locals {
  learn_language_app_hostname = "language.${data.azurerm_key_vault_secret.dns_zone.value}"
}

module "learn_language_postgres_schema" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_postgres_schema?ref=v-102"

  database = local.database
  schema   = "learn_language"
}

module "learn_language_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-102"

  github_repository = "learn-language"
  environment_name  = var.environment_name
  app_name          = "learn-language"
  deployment_secrets = {
    client-storage-config = jsonencode(module.learn_language_client_storage.deployment_config)
    forward-auth-config   = jsonencode(module.learn_language_forward_auth.deployment_config)
  }
  app_secrets = {
    claude-api-key      = sensitive(data.azurerm_key_vault_secret.learn_language_claude_api_key.value)
    eleven-labs-api-key = sensitive(data.azurerm_key_vault_secret.learn_language_eleven_labs_api_key.value)
    google-ai-api-key   = sensitive(data.azurerm_key_vault_secret.learn_language_google_ai_api_key.value)
    ideogram-api-key    = sensitive(data.azurerm_key_vault_secret.learn_language_ideogram_api_key.value)
    openai-api-key      = sensitive(data.azurerm_key_vault_secret.learn_language_openai_api_key.value)
    xai-api-key         = sensitive(data.azurerm_key_vault_secret.learn_language_xai_api_key.value)
  }
  azure_location         = var.azure_location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id  = var.azure_subscription_id
  owner                  = local.owner
  twingate_service_key   = sensitive(module.setup_twingate_access.service_key)
  app_hostname           = local.learn_language_app_hostname
  api_client_id          = module.setup_learn_language_api.client_id
  api_client_secret      = module.setup_learn_language_api.client_secret
  spa_client_id          = module.setup_learn_language_spa.client_id
  api_resource_object_id = module.setup_learn_language_api.resource_object_id
  k8s_oidc_config        = sensitive(module.setup_cluster.k8s_oidc_config)
  client_log_url         = local.client_log_url
}

module "setup_learn_language_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-102"
  owner  = local.owner

  display_name = "Learn Language API"
  roles        = ["readDecks", "createDeck"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "learn-language"
  k8s_service_account_name      = "learn-language-api-workload-identity"
}

module "setup_learn_language_spa" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_spa?ref=v-102"
  owner  = local.owner

  display_name  = "Learn Language SPA"
  redirect_uris = ["https://${local.learn_language_app_hostname}/", "http://localhost:4201/"]

  api_id        = module.setup_learn_language_api.application_id
  api_client_id = module.setup_learn_language_api.client_id
  api_scope_id  = module.setup_learn_language_api.scope_id
}

module "setup_learn_language_web" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_web?ref=v-102"
  owner  = local.owner

  display_name  = "Learn Language Web"
  redirect_uris = ["https://${local.learn_language_app_hostname}/oauth2/callback"]
  api_access = {
    application_id = module.setup_learn_language_api.application_id
    client_id      = module.setup_learn_language_api.client_id
    scope_id       = module.setup_learn_language_api.scope_id
  }
}

module "learn_language_client_storage" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_static_website?ref=v-102"

  name                = "${var.environment_name}langweb${substr(sha256(var.azure_subscription_id), 0, 8)}"
  resource_group_name = var.environment_name
  location            = var.azure_location
  deploy_principal_id = module.learn_language_app_base.deploy_principal_id
  app_origin          = "https://${local.learn_language_app_hostname}"
}

module "learn_language_forward_auth" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_forwardauth?ref=v-102"

  name                = "learn-language"
  namespace           = module.learn_language_app_base.namespace
  hostname            = local.learn_language_app_hostname
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client_id           = module.setup_learn_language_web.client_id
  client_secret       = module.setup_learn_language_web.client_secret
  api_client_id       = module.setup_learn_language_api.client_id
  trusted_proxy_cidrs = nonsensitive(sensitive(local.app_forward_auth).trusted_proxy_cidrs)
  session_redis       = sensitive(local.app_forward_auth).session_redis
  gateway_parent_ref  = sensitive(local.app_forward_auth).gateway_parent_ref
  excluded_routes = [
    {
      path    = "/api/dictionary"
      method  = "POST"
      service = "learn-language-server"
      port    = 8080
    },
    {
      path    = "/api/known-cards"
      method  = "GET"
      service = "learn-language-server"
      port    = 8080
    }
  ]
}

resource "kubernetes_persistent_volume_v1" "learn_language_app_pv" {
  metadata {
    name = "learn-language-app"
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
        path = "/data/learn-language"
      }
    }
  }
}

resource "kubernetes_persistent_volume_v1" "learn_language_backup_pv" {
  metadata {
    name = "learn-language-backup"
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
        path = "/data/learn-language"
      }
    }
  }
}

resource "azurerm_key_vault_secret" "learn_language_db_url" {
  key_vault_id = module.learn_language_app_base.key_vault_id
  name         = "db-url"
  value        = module.learn_language_postgres_schema.jdbc_url
}

resource "azurerm_key_vault_secret" "learn_language_db_username" {
  key_vault_id = module.learn_language_app_base.key_vault_id
  name         = "db-username"
  value        = module.learn_language_postgres_schema.credentials.username
}

resource "azurerm_key_vault_secret" "learn_language_db_password" {
  key_vault_id = module.learn_language_app_base.key_vault_id
  name         = "db-password"
  value        = module.learn_language_postgres_schema.credentials.password
}

resource "random_bytes" "learn_language_token_encryption_key" {
  length = 32
}

resource "azurerm_key_vault_secret" "learn_language_token_encryption_key" {
  key_vault_id = module.learn_language_app_base.key_vault_id
  name         = "token-encryption-key"
  value        = random_bytes.learn_language_token_encryption_key.base64
}
