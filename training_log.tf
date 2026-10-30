# Application-owned infrastructure; reusable modules remain pinned to v-101.

locals {
  training_log_app_hostname = "training.${data.azurerm_key_vault_secret.dns_zone.value}"
}

module "training_log_postgres_schema" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_postgres_schema?ref=v-101"

  database = local.database
  schema   = "training_log"
}

module "training_log_app_base" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_base?ref=v-101"

  github_repository = "training-log-pro"
  environment_name  = var.environment_name
  app_name          = "training-log"
  app_secrets = {
    strava-client-id       = sensitive(data.azurerm_key_vault_secret.training_log_strava_client_id.value)
    strava-client-secret   = sensitive(data.azurerm_key_vault_secret.training_log_strava_client_secret.value)
    withings-client-id     = sensitive(data.azurerm_key_vault_secret.training_log_withings_client_id.value)
    withings-client-secret = sensitive(data.azurerm_key_vault_secret.training_log_withings_client_secret.value)
  }
  azure_location         = var.azure_location
  tenant_id              = data.azurerm_client_config.current.tenant_id
  azure_subscription_id  = var.azure_subscription_id
  owner                  = local.owner
  twingate_service_key   = sensitive(module.setup_twingate_access.service_key)
  app_hostname           = local.training_log_app_hostname
  api_client_id          = module.setup_training_log_api.client_id
  api_client_secret      = module.setup_training_log_api.client_secret
  spa_client_id          = module.setup_training_log_spa.client_id
  api_resource_object_id = module.setup_training_log_api.resource_object_id
  k8s_oidc_config        = sensitive(module.setup_cluster.k8s_oidc_config)
  client_log_url         = local.client_log_url
}

module "setup_training_log_api" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-101"
  owner  = local.owner

  display_name = "Training Log API"
  roles        = ["readWorkouts", "createWorkout"]

  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = "training-log"
  k8s_service_account_name      = "training-log-api-workload-identity"
}

module "setup_training_log_spa" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_spa?ref=v-101"
  owner  = local.owner

  display_name  = "Training Log SPA"
  redirect_uris = ["https://${local.training_log_app_hostname}/", "http://localhost:4203/"]

  api_id        = module.setup_training_log_api.application_id
  api_client_id = module.setup_training_log_api.client_id
  api_scope_id  = module.setup_training_log_api.scope_id
}

resource "kubernetes_persistent_volume_v1" "training_log_app_pv" {
  metadata {
    name = "training-log-app"
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
        path = "/data/training-log"
      }
    }
  }
}

resource "kubernetes_persistent_volume_v1" "training_log_backup_pv" {
  metadata {
    name = "training-log-backup"
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
        path = "/data/training-log"
      }
    }
  }
}

resource "azurerm_key_vault_secret" "training_log_db_url" {
  key_vault_id = module.training_log_app_base.key_vault_id
  name         = "db-url"
  value        = module.training_log_postgres_schema.jdbc_url
}

resource "azurerm_key_vault_secret" "training_log_db_username" {
  key_vault_id = module.training_log_app_base.key_vault_id
  name         = "db-username"
  value        = module.training_log_postgres_schema.credentials.username
}

resource "azurerm_key_vault_secret" "training_log_db_password" {
  key_vault_id = module.training_log_app_base.key_vault_id
  name         = "db-password"
  value        = module.training_log_postgres_schema.credentials.password
}

resource "random_bytes" "training_log_token_encryption_key" {
  length = 32
}

resource "azurerm_key_vault_secret" "training_log_token_encryption_key" {
  key_vault_id = module.training_log_app_base.key_vault_id
  name         = "token-encryption-key"
  value        = random_bytes.training_log_token_encryption_key.base64
}
