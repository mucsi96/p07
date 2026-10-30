# Application-owned infrastructure; reusable modules remain pinned to v-101.

locals {
  cooking_app_hostname      = "cooking.${data.azurerm_key_vault_secret.dns_zone.value}"
  cooking_browser_client_id = nonsensitive(sensitive(local.app_forward_auth) == null) ? module.setup_cooking_spa[0].client_id : module.setup_cooking_web[0].client_id
}

module "cooking_postgres_schema" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_postgres_schema?ref=v-101"

  database = local.database
  schema   = "cooking"
}

module "cooking_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-101"

  github_repository = "cooking-app"
  environment_name  = var.environment_name
  app_name          = "cooking"
  app_secrets = {
    claude-api-key = sensitive(data.azurerm_key_vault_secret.cooking_claude_api_key.value)
    openai-api-key = sensitive(data.azurerm_key_vault_secret.cooking_openai_api_key.value)
  }
  deployment_secrets = nonsensitive(sensitive(local.app_forward_auth) == null) ? {} : {
    client-storage-config = jsonencode(module.cooking_client_storage.deployment_config)
    forward-auth-config   = jsonencode(module.cooking_forward_auth[0].deployment_config)
  }
  azure_location         = var.azure_location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id  = var.azure_subscription_id
  owner                  = local.owner
  twingate_service_key   = sensitive(module.setup_twingate_access.service_key)
  app_hostname           = local.cooking_app_hostname
  api_client_id          = module.setup_cooking_api.client_id
  api_client_secret      = module.setup_cooking_api.client_secret
  spa_client_id          = local.cooking_browser_client_id
  api_resource_object_id = module.setup_cooking_api.resource_object_id
  k8s_oidc_config        = sensitive(module.setup_cluster.k8s_oidc_config)
  client_log_url         = "https://${local.cooking_hostname}${module.setup_victoria_logs.faro_client_path}"
}

module "cooking_client_storage" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_static_website?ref=v-101"

  name                = "${var.environment_name}cookweb${substr(sha256(var.azure_subscription_id), 0, 8)}"
  resource_group_name = var.environment_name
  location            = var.azure_location
  deploy_principal_id = module.cooking_app_base.deploy_principal_id
  app_origin          = "https://${local.cooking_app_hostname}"
}

module "setup_cooking_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-101"
  owner  = local.owner

  display_name = "Cooking API"
  roles        = ["readRecipes", "createRecipe"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "cooking"
  k8s_service_account_name      = "cooking-api-workload-identity"
}

module "setup_cooking_spa" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_spa?ref=v-101"
  count  = nonsensitive(sensitive(local.app_forward_auth) == null ? 1 : 0)
  owner  = local.owner

  display_name  = "Cooking SPA"
  redirect_uris = ["https://${local.cooking_app_hostname}/", "http://localhost:4260/"]

  api_id        = module.setup_cooking_api.application_id
  api_client_id = module.setup_cooking_api.client_id
  api_scope_id  = module.setup_cooking_api.scope_id
}

module "setup_cooking_web" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_web?ref=v-101"
  count  = nonsensitive(sensitive(local.app_forward_auth) == null ? 0 : 1)
  owner  = local.owner

  display_name  = "Cooking Web"
  redirect_uris = ["https://${local.cooking_app_hostname}/oauth2/callback"]
  api_access = {
    application_id = module.setup_cooking_api.application_id
    client_id      = module.setup_cooking_api.client_id
    scope_id       = module.setup_cooking_api.scope_id
  }
  allowed_user_ids = toset([for user in data.azuread_users.cooking_all.users : user.object_id])
}

module "cooking_forward_auth" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_forwardauth?ref=v-101"
  count  = nonsensitive(sensitive(local.app_forward_auth) == null ? 0 : 1)

  name                = "cooking"
  namespace           = module.cooking_app_base.namespace
  hostname            = local.cooking_app_hostname
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client_id           = module.setup_cooking_web[0].client_id
  client_secret       = module.setup_cooking_web[0].client_secret
  api_client_id       = module.setup_cooking_api.client_id
  trusted_proxy_cidrs = nonsensitive(sensitive(local.app_forward_auth).trusted_proxy_cidrs)
  session_redis       = sensitive(local.app_forward_auth).session_redis
  gateway_parent_ref  = sensitive(local.app_forward_auth).gateway_parent_ref
}

# Every user in the tenant gets both recipe roles — the whole household uses
# the cooking app. register_api already assigns all roles to the owner, so
# the owner is excluded here to avoid a duplicate assignment.
data "azuread_users" "cooking_all" {
  return_all = true
}

resource "azuread_app_role_assignment" "cooking_all_users" {
  for_each = {
    for pair in setproduct(
      ["readRecipes", "createRecipe"],
      [for user in data.azuread_users.cooking_all.users : user.object_id if user.object_id != local.owner]
    ) : "${pair[0]}-${pair[1]}" => pair
  }

  app_role_id         = module.setup_cooking_api.roles_ids[each.value[0]]
  principal_object_id = each.value[1]
  resource_object_id  = module.setup_cooking_api.resource_object_id
}

resource "kubernetes_persistent_volume_v1" "cooking_app_pv" {
  metadata {
    name = "cooking-app"
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
        path = "/data/cooking"
      }
    }
  }
}

resource "kubernetes_persistent_volume_v1" "cooking_backup_pv" {
  metadata {
    name = "cooking-backup"
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
        path = "/data/cooking"
      }
    }
  }
}

resource "azurerm_key_vault_secret" "cooking_db_url" {
  key_vault_id = module.cooking_app_base.key_vault_id
  name         = "db-url"
  value        = module.cooking_postgres_schema.jdbc_url
}

resource "azurerm_key_vault_secret" "cooking_db_username" {
  key_vault_id = module.cooking_app_base.key_vault_id
  name         = "db-username"
  value        = module.cooking_postgres_schema.credentials.username
}

resource "azurerm_key_vault_secret" "cooking_db_password" {
  key_vault_id = module.cooking_app_base.key_vault_id
  name         = "db-password"
  value        = module.cooking_postgres_schema.credentials.password
}
