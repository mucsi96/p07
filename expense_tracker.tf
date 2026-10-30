# Application-owned infrastructure; reusable modules remain pinned to v-101.

locals {
  expense_tracker_app_hostname = "expenses.${data.azurerm_key_vault_secret.dns_zone.value}"
}

module "expense_tracker_postgres_schema" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_postgres_schema?ref=v-101"

  database = local.database
  schema   = "expensetracker"
}

module "expense_tracker_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-101"

  github_repository      = "expense-tracker"
  environment_name       = var.environment_name
  app_name               = "expense-tracker"
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
  client_log_url         = local.client_log_url
}

module "setup_expense_tracker_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-101"
  owner  = local.owner

  display_name = "Expense Tracker API"
  roles        = ["readExpenses", "createExpenses", "deleteExpenses"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "expense-tracker"
  k8s_service_account_name      = "expense-tracker-api-workload-identity"
}

module "setup_expense_tracker_spa" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_spa?ref=v-101"
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
