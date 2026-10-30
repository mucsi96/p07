# Application-owned infrastructure; reusable modules remain pinned to v-101.

locals {
  backup_databases = [
    merge(local.backup_db, sensitive(module.learn_language_postgres_schema.credentials), {
      name            = "Learn language"
      schema          = "learn_language"
      createPlainDump = true
      folderBackups = [
        {
          path = "/app/storage/learn-language"
        }
      ]
      excludeTables = [
        "study_sessions",
        "study_session_cards",
        "model_usage_logs",
        "api_tokens"
      ]
    }),
    merge(local.backup_db, sensitive(module.training_log_postgres_schema.credentials), {
      name            = "Training log"
      schema          = "training_log"
      createPlainDump = true
      excludeTables = [
        "oauth2_authorized_client"
      ]
    }),
    merge(local.backup_db, module.setup_victoria_metrics.database_credentials, {
      name            = "Grafana"
      schema          = "grafana",
      createPlainDump = true
    }),
    merge(local.backup_db, sensitive(module.library_postgres_schema.credentials), {
      name            = "Library"
      schema          = "library"
      createPlainDump = true,
      folderBackups = [
        {
          path = "/app/storage/library"
        }
      ]
    }),
    merge(local.backup_db, sensitive(module.expense_tracker_postgres_schema.credentials), {
      name            = "Expense tracker"
      schema          = "expensetracker"
      createPlainDump = true
    }),
    merge(local.backup_db, sensitive(module.cooking_postgres_schema.credentials), {
      name            = "Cooking"
      schema          = "cooking"
      createPlainDump = true
      folderBackups = [
        {
          path = "/app/storage/cooking"
        }
      ]
    }),
    merge(local.backup_db, sensitive(module.hello_postgres_schema.credentials), {
      name            = "Hello"
      schema          = "hello"
      createPlainDump = true
    }),
  ]
  # Match the former list(object) input's optional attributes in the stored JSON.
  backup_dbs_config = [for db in local.backup_databases : merge({
    createPlainDump = null
    folderBackups   = null
    excludeTables   = null
  }, db)]
}

locals {
  backup_app_hostname = "backup.${data.azurerm_key_vault_secret.dns_zone.value}"
}

module "backup_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-101"

  github_repository      = "postgres-azure-backup"
  environment_name       = var.environment_name
  app_name               = "backup"
  azure_location         = var.azure_location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id  = var.azure_subscription_id
  owner                  = local.owner
  twingate_service_key   = sensitive(module.setup_twingate_access.service_key)
  app_hostname           = local.backup_app_hostname
  api_client_id          = module.setup_backup_api.client_id
  api_client_secret      = module.setup_backup_api.client_secret
  spa_client_id          = module.setup_backup_spa.client_id
  api_resource_object_id = module.setup_backup_api.resource_object_id
  k8s_oidc_config        = sensitive(module.setup_cluster.k8s_oidc_config)
  client_log_url         = local.client_log_url
}

module "setup_backup_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-101"
  owner  = local.owner

  display_name = "Backup API"
  roles        = ["readBackups", "createBackup", "cleanupBackups", "restoreBackup", "downloadBackup"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "backup"
  k8s_service_account_name      = "postgres-azure-backup-api-workload-identity"
}

module "setup_backup_spa" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_spa?ref=v-101"
  owner  = local.owner

  display_name  = "Backup SPA"
  redirect_uris = ["https://${local.backup_app_hostname}/", "http://localhost:4202/"]

  api_id        = module.setup_backup_api.application_id
  api_client_id = module.setup_backup_api.client_id
  api_scope_id  = module.setup_backup_api.scope_id
}

data "azurerm_storage_account" "backup_storage_account" {
  name                = "ibari"
  resource_group_name = "ibari"
}

data "azurerm_storage_container" "backup_backups_storage_container" {
  name               = "backups"
  storage_account_id = data.azurerm_storage_account.backup_storage_account.id
}

resource "azurerm_role_assignment" "backup_allow_backup_api_to_write_storage_container" {
  scope                = data.azurerm_storage_container.backup_backups_storage_container.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.setup_backup_api.resource_object_id
}

resource "azurerm_key_vault_secret" "backup_dbs_config" {
  key_vault_id = module.backup_app_base.key_vault_id
  name         = "dbs-config"
  value        = jsonencode(sensitive(local.backup_dbs_config))
}

resource "azurerm_key_vault_secret" "backup_storage_account_blob_url" {
  key_vault_id = module.backup_app_base.key_vault_id
  name         = "storage-account-blob-url"
  value        = data.azurerm_storage_account.backup_storage_account.primary_blob_endpoint
}

resource "azurerm_key_vault_secret" "backup_storage_account_container_name" {
  key_vault_id = module.backup_app_base.key_vault_id
  name         = "storage-account-container-name"
  value        = data.azurerm_storage_container.backup_backups_storage_container.name
}
