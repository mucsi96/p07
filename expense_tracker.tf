# Application-owned infrastructure; reusable modules remain pinned to v-102.

locals {
  expense_tracker_app_hostname = "expenses.${data.azurerm_key_vault_secret.dns_zone.value}"
}

module "expense_tracker_postgres_schema" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_postgres_schema?ref=v-104"

  database = local.database
  schema   = "expensetracker"
}

module "expense_tracker_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-104"

  github_repository = "expense-tracker"
  environment_name  = var.environment_name
  app_name          = "expense-tracker"
  deployment_secrets = {
    client-storage-config = jsonencode(module.expense_tracker_client_storage.deployment_config)
    forward-auth-config   = jsonencode(module.expense_tracker_forward_auth.deployment_config)
  }
  azure_location         = var.azure_location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id  = var.azure_subscription_id
  owner                  = local.owner
  twingate_service_key   = sensitive(module.setup_twingate_access.service_key)
  app_hostname           = local.expense_tracker_app_hostname
  api_client_id          = module.setup_expense_tracker_api.client_id
  api_client_secret      = module.setup_expense_tracker_api.client_secret
  spa_client_id          = module.setup_expense_tracker_spa.client_id
  api_resource_object_id = module.setup_expense_tracker_api.resource_object_id
  k8s_oidc_config        = sensitive(module.setup_cluster.k8s_oidc_config)
  client_log_url         = "https://${local.expense_tracker_app_hostname}${module.setup_victoria_logs.faro_client_path}"
}

module "expense_tracker_client_storage" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_static_website?ref=v-104"

  name                = "${var.environment_name}expenses${substr(sha256(var.azure_subscription_id), 0, 8)}"
  resource_group_name = var.environment_name
  location            = var.azure_location
  deploy_principal_id = module.expense_tracker_app_base.deploy_principal_id
  app_origin          = "https://${local.expense_tracker_app_hostname}"
}

module "setup_expense_tracker_web" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_web?ref=v-104"
  owner  = local.owner

  display_name  = "Expense Tracker Web"
  redirect_uris = ["https://${local.expense_tracker_app_hostname}/oauth2/callback"]
  api_access = {
    application_id = module.setup_expense_tracker_api.application_id
    client_id      = module.setup_expense_tracker_api.client_id
    scope_id       = module.setup_expense_tracker_api.scope_id
  }
}

module "expense_tracker_forward_auth" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_forwardauth?ref=v-104"

  name                = "expense-tracker"
  namespace           = module.expense_tracker_app_base.namespace
  hostname            = local.expense_tracker_app_hostname
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client_id           = module.setup_expense_tracker_web.client_id
  client_secret       = module.setup_expense_tracker_web.client_secret
  api_client_id       = module.setup_expense_tracker_api.client_id
  trusted_proxy_cidrs = nonsensitive(sensitive(local.app_forward_auth).trusted_proxy_cidrs)
  session_redis       = sensitive(local.app_forward_auth).session_redis
  gateway_parent_ref  = sensitive(local.app_forward_auth).gateway_parent_ref
  excluded_routes = [{
    path    = local.bank_notifications_path
    method  = "POST"
    service = "expense-tracker-server"
    port    = 8080
  }]
}

module "setup_expense_tracker_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-104"
  owner  = local.owner

  display_name = "Expense Tracker API"
  roles        = ["readExpenses", "createExpenses", "deleteExpenses"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "expense-tracker"
  k8s_service_account_name      = "expense-tracker-api-workload-identity"
}

# Retain the old registration during cutover so the currently deployed SPA
# remains usable until the application PR is deployed. Remove in a follow-up.
module "setup_expense_tracker_spa" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_spa?ref=v-104"
  owner  = local.owner

  display_name  = "Expense Tracker SPA"
  redirect_uris = ["https://${local.expense_tracker_app_hostname}/", "http://localhost:4205/"]

  api_id        = module.setup_expense_tracker_api.application_id
  api_client_id = module.setup_expense_tracker_api.client_id
  api_scope_id  = module.setup_expense_tracker_api.scope_id
}

resource "kubernetes_persistent_volume_v1" "expense_tracker_app_pv" {
  metadata {
    name = "expense-tracker-app"
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
        path = "/data/expense-tracker"
      }
    }
  }
}

resource "kubernetes_persistent_volume_v1" "expense_tracker_backup_pv" {
  metadata {
    name = "expense-tracker-backup"
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
        path = "/data/expense-tracker"
      }
    }
  }
}

resource "azurerm_key_vault_secret" "expense_tracker_db_url" {
  key_vault_id = module.expense_tracker_app_base.key_vault_id
  name         = "db-url"
  value        = module.expense_tracker_postgres_schema.jdbc_url
}

resource "azurerm_key_vault_secret" "expense_tracker_db_username" {
  key_vault_id = module.expense_tracker_app_base.key_vault_id
  name         = "db-username"
  value        = module.expense_tracker_postgres_schema.credentials.username
}

resource "azurerm_key_vault_secret" "expense_tracker_db_password" {
  key_vault_id = module.expense_tracker_app_base.key_vault_id
  name         = "db-password"
  value        = module.expense_tracker_postgres_schema.credentials.password
}

# Shared bearer token for the bank email notification endpoint. The
# Cloudflare Email Worker in bank_email_worker.tf sends it in the
# Authorization header; the API reads this secret to validate it.
resource "random_password" "expense_tracker_bank_notification_token" {
  length  = 64
  special = false
}

resource "azurerm_key_vault_secret" "expense_tracker_bank_notification_token" {
  key_vault_id = module.expense_tracker_app_base.key_vault_id
  name         = "bank-notification-token"
  value        = random_password.expense_tracker_bank_notification_token.result
}
