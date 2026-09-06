terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.4.0, < 6.0.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.16.1"
    }

    http = {
      source  = "hashicorp/http"
      version = ">= 3.6.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.6"
    }

    ansible = {
      source  = "ansible/ansible"
      version = ">= 1.3.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.19.1"
    }

    twingate = {
      source  = "Twingate/twingate"
      version = "4.2.1"
    }

    github = {
      source  = "integrations/github"
      version = ">= 6.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }

  }

  required_version = ">= 1.4"
}

provider "random" {}

provider "azurerm" {
  features {
    enhanced_validation {
      locations          = true
      resource_providers = true
    }
  }

  subscription_id                 = var.azure_subscription_id
  tenant_id                       = var.azure_tenant_id
  use_cli                         = true
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

provider "azuread" {}

provider "ansible" {}

data "azurerm_client_config" "current" {}

data "azurerm_key_vault" "kv" {
  resource_group_name = var.environment_name
  name                = var.environment_name
}

data "azurerm_key_vault_secret" "dns_zone" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "dns-zone"
}

data "azurerm_key_vault_secret" "cloudflare_zone_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "cloudflare-zone-id"
}

data "azurerm_key_vault_secret" "cloudflare_api_token" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "cloudflare-api-token"
}

data "azurerm_key_vault_secret" "authorized_as" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "authorized-as"
}

data "azurerm_key_vault_secret" "github_token" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "github-token"
}

data "azurerm_key_vault_secret" "letsencrypt_email" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "letsencrypt-email"
}

data "azurerm_key_vault_secret" "twingate_network" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "twingate-network"
}

data "azurerm_key_vault_secret" "twingate_api_token" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "twingate-api-token"
}

data "azurerm_key_vault_secret" "netcup_server_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "netcup-server-id"
}

data "azurerm_key_vault_secret" "netcup_user_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "netcup-user-id"
}

data "azurerm_key_vault_secret" "netcup_refresh_token" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "netcup-refresh-token"
}

data "azurerm_key_vault_secret" "netcup_image_flavour_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "netcup-image-flavour-id"
}

data "azurerm_key_vault_secret" "netcup_disk_name" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "netcup-disk-name"
}

data "azurerm_key_vault_secret" "hello_claude_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "hello-claude-api-key"
}

data "azurerm_key_vault_secret" "learn_language_claude_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "learn-language-claude-api-key"
}

data "azurerm_key_vault_secret" "learn_language_eleven_labs_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "learn-language-eleven-labs-api-key"
}

data "azurerm_key_vault_secret" "learn_language_google_ai_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "learn-language-google-ai-api-key"
}

data "azurerm_key_vault_secret" "learn_language_ideogram_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "learn-language-ideogram-api-key"
}

data "azurerm_key_vault_secret" "learn_language_openai_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "learn-language-openai-api-key"
}

data "azurerm_key_vault_secret" "learn_language_xai_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "learn-language-xai-api-key"
}

data "azurerm_key_vault_secret" "training_log_strava_client_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "training-log-strava-client-id"
}

data "azurerm_key_vault_secret" "training_log_strava_client_secret" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "training-log-strava-client-secret"
}

data "azurerm_key_vault_secret" "training_log_withings_client_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "training-log-withings-client-id"
}

data "azurerm_key_vault_secret" "training_log_withings_client_secret" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "training-log-withings-client-secret"
}

data "azurerm_key_vault_secret" "library_openai_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "library-openai-api-key"
}

data "azurerm_key_vault_secret" "cooking_claude_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "cooking-claude-api-key"
}

data "azurerm_key_vault_secret" "cooking_openai_api_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "cooking-openai-api-key"
}

locals {
  grafana_hostname = "grafana.${data.azurerm_key_vault_secret.dns_zone.value}"
  faro_hostname    = "faro.${data.azurerm_key_vault_secret.dns_zone.value}"
  # /collect is the path the Faro Web SDK POSTs telemetry to. Stored verbatim
  # in each app's Key Vault so the SPA can use it without further URL juggling.
  client_log_url = "https://${local.faro_hostname}/collect"

  oauth2_proxy_chart_version = "10.4.3"  #https://github.com/oauth2-proxy/manifests/releases
  oauth2_proxy_image_version = "v7.15.2" #https://github.com/oauth2-proxy/oauth2-proxy/releases

  expense_tracker_hostname = "expenses.${data.azurerm_key_vault_secret.dns_zone.value}"
  bank_notifications_path  = "/api/bank-notifications"
}

provider "kubernetes" {
  host                   = module.setup_cluster.k8s_host
  client_certificate     = module.setup_cluster.k8s_client_certificate
  client_key             = module.setup_cluster.k8s_client_key
  cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = module.setup_cluster.k8s_host
    client_certificate     = module.setup_cluster.k8s_client_certificate
    client_key             = module.setup_cluster.k8s_client_key
    cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  }
}

# Used in place of hashicorp/kubernetes's kubernetes_manifest for CRDs such as
# Gateway API resources. kubernetes_manifest opens a REST client at plan
# time and breaks the from-scratch apply because the cluster does not exist
# yet; kubectl_manifest defers the connection to apply time.
provider "kubectl" {
  host                   = module.setup_cluster.k8s_host
  client_certificate     = module.setup_cluster.k8s_client_certificate
  client_key             = module.setup_cluster.k8s_client_key
  cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  load_config_file       = false
}

provider "cloudflare" {
  api_token = data.azurerm_key_vault_secret.cloudflare_api_token.value
}

provider "twingate" {
  api_token = data.azurerm_key_vault_secret.twingate_api_token.value
  network   = data.azurerm_key_vault_secret.twingate_network.value
}

provider "github" {
  owner = "mucsi96"
  token = data.azurerm_key_vault_secret.github_token.value
}

data "cloudflare_ip_ranges" "cloudflare" {}

# Created before the server: its connector tokens are baked into the Netcup
# installation script. No depends_on; it must not order after setup_cluster.
module "setup_twingate_connector" {
  source           = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_twingate_connector?ref=v-68"
  environment_name = var.environment_name
}

# Needs the server's address/port, so it orders after provision_server
# via field references. No depends_on (would cycle with ssh_ready_wait_for).
module "setup_twingate_access" {
  source            = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_twingate_access?ref=v-68"
  environment_name  = var.environment_name
  remote_network_id = module.setup_twingate_connector.remote_network_id
  k8s_host          = module.provision_server.ipv4_address
  k8s_port          = 6443
  ssh_address       = module.provision_server.ipv4_address
  ssh_port          = module.provision_server.ssh_port
}

module "provision_server" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/provision_server?ref=v-68"

  server_name             = var.environment_name
  netcup_server_id        = tonumber(data.azurerm_key_vault_secret.netcup_server_id.value)
  netcup_user_id          = tonumber(data.azurerm_key_vault_secret.netcup_user_id.value)
  netcup_refresh_token    = data.azurerm_key_vault_secret.netcup_refresh_token.value
  netcup_image_flavour_id = tonumber(data.azurerm_key_vault_secret.netcup_image_flavour_id.value)
  netcup_disk_name        = data.azurerm_key_vault_secret.netcup_disk_name.value
  reinstall_generation    = "initial"
  https_source_ips        = concat(data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs, data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs)
  twingate_network        = data.azurerm_key_vault_secret.twingate_network.value
  twingate_access_token   = module.setup_twingate_connector.access_token
  twingate_refresh_token  = module.setup_twingate_connector.refresh_token
  ssh_ready_wait_for = join(",", [
    module.setup_twingate_access.ssh_resource_id,
    module.setup_twingate_access.k8s_resource_id,
  ])
}

module "setup_cluster" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_cluster?ref=v-68"

  host                     = module.provision_server.ipv4_address
  ssh_port                 = module.provision_server.ssh_port
  username                 = module.provision_server.username
  azure_key_vault_name     = data.azurerm_key_vault.kv.name
  environment_name         = var.environment_name
  azure_subscription_id    = var.azure_subscription_id
  storage_account_name     = var.storage_account_name
  azure_tenant_id          = data.azurerm_client_config.current.tenant_id
  owner                    = local.owner
  local_python_interpreter = abspath("${path.root}/.venv/bin/python3")
  wait_for                 = module.provision_server.ssh_ready
}

module "create_redis_namespace" {
  source        = "git::https://github.com/mucsi96/k8s-modules.git//modules/create_app_namespace?ref=v-68"
  k8s_namespace = "redis"
}

module "create_redis" {
  source        = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_redis?ref=v-68"
  k8s_name      = "redis"
  k8s_namespace = module.create_redis_namespace.k8s_namespace
}

module "setup_ingress_controller" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_ingress_controller?ref=v-68"

  dns_zone              = data.azurerm_key_vault_secret.dns_zone.value
  k8s_config            = module.setup_cluster.k8s_config
  cloudflare_zone_id    = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  origin_ipv4           = module.provision_server.ipv4_address
  cloudflare_ipv4_cidrs = data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs
  cloudflare_ipv6_cidrs = data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs
  authorized_as         = data.azurerm_key_vault_secret.authorized_as.value
  edge_firewall_exceptions = [
    {
      description = "Allow the bank email worker to POST notifications to the expense tracker"
      hostname    = local.expense_tracker_hostname
      path        = local.bank_notifications_path
    }
  ]
}

module "create_database_namespace" {
  source        = "git::https://github.com/mucsi96/k8s-modules.git//modules/create_app_namespace?ref=v-68"
  k8s_namespace = "db"
}

module "setup_monitoring_crds" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_monitoring_crds?ref=v-68"

  prometheus_operator_crds_chart_version = "28.0.1" #https://github.com/prometheus-community/helm-charts/releases?q=prometheus-operator-crds
  wait_for                               = module.setup_ingress_controller.ingress_controller_ready
}

module "create_database" {
  source        = "git::https://github.com/mucsi96/k8s-modules.git//modules/create_postgres_database?ref=v-68"
  k8s_name      = "postgres1"
  k8s_namespace = module.create_database_namespace.k8s_namespace
  db_name       = "postgres1"
  application_schemas = [
    "cooking",
    "expensetracker",
    "grafana",
    "hello",
    "learn_language",
    "library",
    "training_log",
  ]
  admin_password_active_slot      = "green"
  admin_password_blue_generation  = null
  admin_password_green_generation = "initial"
  role_provisioning_generation    = "initial"

  wait_for = module.setup_monitoring_crds.crds_ready
}

locals {
  owner = data.azurerm_client_config.current.object_id
  db = {
    host     = module.create_database.host
    port     = module.create_database.port
    database = module.create_database.name
  }
  db_credentials = module.create_database.schema_credentials
}

moved {
  from = module.setup_victoria_metrics.random_password.grafana_db_password
  to   = module.create_database.random_password.schema_owner["grafana"]
}

module "register_grafana_dashboard" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_webapp?ref=v-68"

  display_name  = "Grafana - ${var.environment_name}"
  owner         = local.owner
  redirect_uris = ["https://${local.grafana_hostname}/oauth2/callback"]
}

module "setup_victoria_metrics" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_victoria_metrics?ref=v-68"

  grafana_hostname                         = local.grafana_hostname
  tenant_id                                = data.azurerm_client_config.current.tenant_id
  grafana_client_id                        = module.register_grafana_dashboard.client_id
  grafana_client_secret                    = module.register_grafana_dashboard.client_secret
  valid_email                              = data.azurerm_key_vault_secret.letsencrypt_email.value
  victoria_metrics_k8s_stack_chart_version = "0.91.2" #https://github.com/VictoriaMetrics/helm-charts/releases?q=victoria-metrics-k8s-stack
  oauth2_proxy_chart_version               = local.oauth2_proxy_chart_version
  oauth2_proxy_image_version               = local.oauth2_proxy_image_version
  session_redis = {
    connection_url = module.create_redis.connection_url
    password       = module.create_redis.password
  }
  database = {
    host     = local.db.host
    port     = local.db.port
    name     = local.db.database
    username = local.db_credentials["grafana"].username
    password = local.db_credentials["grafana"].password
  }
  gateway_parent_ref = module.setup_ingress_controller.gateway_parent_ref
  wait_for           = module.setup_ingress_controller.ingress_controller_ready
}

module "setup_victoria_logs" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_victoria_logs?ref=v-68"

  alloy_chart_version = "1.8.1" #https://github.com/grafana/helm-charts/releases?q=alloy
  # In-cluster VLSingle API URL owned by the stack module; Alloy pushes both
  # pod logs and Faro browser telemetry to its Loki-compatible endpoint.
  victoria_logs_url = module.setup_victoria_metrics.victoria_logs_url
  faro_hostname     = local.faro_hostname
  faro_cors_allowed_origins = [
    "https://*.${data.azurerm_key_vault_secret.dns_zone.value}",
  ]
  gateway_parent_ref = module.setup_ingress_controller.gateway_parent_ref
  wait_for           = module.setup_victoria_metrics.victoria_metrics_k8s_stack_ready
}

module "setup_backup_app" {
  source                = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_backup_app?ref=v-68"
  environment_name      = var.environment_name
  azure_location        = var.azure_location
  owner                 = local.owner
  k8s_oidc_issuer_url   = module.setup_cluster.oidc_issuer_url
  hostname              = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id = var.azure_subscription_id
  tenant_id             = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config       = module.setup_cluster.k8s_oidc_config
  client_log_url        = local.client_log_url
  twingate_service_key  = module.setup_twingate_access.service_key

  azure_storage_account_resource_group_name = "ibari"
  azure_storage_account_name                = "ibari"

  dbs_config = [
    merge(local.db, local.db_credentials["learn_language"], {
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
    merge(local.db, local.db_credentials["training_log"], {
      name            = "Training log"
      schema          = "training_log"
      createPlainDump = true
      excludeTables = [
        "oauth2_authorized_client"
      ]
    }),
    merge(local.db, local.db_credentials["grafana"], {
      name            = "Grafana"
      schema          = "grafana",
      createPlainDump = true
    }),
    merge(local.db, local.db_credentials["library"], {
      name            = "Library"
      schema          = "library"
      createPlainDump = true,
      folderBackups = [
        {
          path = "/app/storage/library"
        }
      ]
    }),
    merge(local.db, local.db_credentials["expensetracker"], {
      name            = "Expense tracker"
      schema          = "expensetracker"
      createPlainDump = true
    }),
    merge(local.db, local.db_credentials["cooking"], {
      name            = "Cooking"
      schema          = "cooking"
      createPlainDump = true
      folderBackups = [
        {
          path = "/app/storage/cooking"
        }
      ]
    }),
    merge(local.db, local.db_credentials["hello"], {
      name            = "Hello"
      schema          = "hello"
      createPlainDump = true
    }),
  ]
}

module "setup_learn_language_app" {
  source                = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_learn_language_app?ref=v-68"
  environment_name      = var.environment_name
  azure_location        = var.azure_location
  claude_api_key        = data.azurerm_key_vault_secret.learn_language_claude_api_key.value
  eleven_labs_api_key   = data.azurerm_key_vault_secret.learn_language_eleven_labs_api_key.value
  google_ai_api_key     = data.azurerm_key_vault_secret.learn_language_google_ai_api_key.value
  ideogram_api_key      = data.azurerm_key_vault_secret.learn_language_ideogram_api_key.value
  openai_api_key        = data.azurerm_key_vault_secret.learn_language_openai_api_key.value
  xai_api_key           = data.azurerm_key_vault_secret.learn_language_xai_api_key.value
  owner                 = local.owner
  k8s_oidc_issuer_url   = module.setup_cluster.oidc_issuer_url
  hostname              = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id = var.azure_subscription_id
  tenant_id             = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config       = module.setup_cluster.k8s_oidc_config
  client_log_url        = local.client_log_url
  db_jdbc_url           = module.create_database.jdbc_url
  db_username           = local.db_credentials["learn_language"].username
  db_password           = local.db_credentials["learn_language"].password
  twingate_service_key  = module.setup_twingate_access.service_key
}

module "setup_hello_app" {
  source                = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_hello_app?ref=v-68"
  environment_name      = var.environment_name
  azure_location        = var.azure_location
  claude_api_key        = data.azurerm_key_vault_secret.hello_claude_api_key.value
  owner                 = local.owner
  k8s_oidc_issuer_url   = module.setup_cluster.oidc_issuer_url
  hostname              = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id = var.azure_subscription_id
  tenant_id             = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config       = module.setup_cluster.k8s_oidc_config
  client_log_url        = local.client_log_url
  db_jdbc_url           = module.create_database.jdbc_url
  db_username           = local.db_credentials["hello"].username
  db_password           = local.db_credentials["hello"].password
  twingate_service_key  = module.setup_twingate_access.service_key
}

module "setup_training_log_app" {
  source                 = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_training_log_app?ref=v-68"
  environment_name       = var.environment_name
  azure_location         = var.azure_location
  strava_client_id       = data.azurerm_key_vault_secret.training_log_strava_client_id.value
  strava_client_secret   = data.azurerm_key_vault_secret.training_log_strava_client_secret.value
  withings_client_id     = data.azurerm_key_vault_secret.training_log_withings_client_id.value
  withings_client_secret = data.azurerm_key_vault_secret.training_log_withings_client_secret.value
  owner                  = local.owner
  k8s_oidc_issuer_url    = module.setup_cluster.oidc_issuer_url
  hostname               = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id  = var.azure_subscription_id
  tenant_id              = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config        = module.setup_cluster.k8s_oidc_config
  client_log_url         = local.client_log_url
  db_jdbc_url            = module.create_database.jdbc_url
  db_username            = local.db_credentials["training_log"].username
  db_password            = local.db_credentials["training_log"].password
  twingate_service_key   = module.setup_twingate_access.service_key
}

module "setup_bank_email_worker" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_bank_email_worker?ref=v-68"

  cloudflare_zone_id = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  dns_zone           = data.azurerm_key_vault_secret.dns_zone.value
  target_url         = "https://${local.expense_tracker_hostname}${local.bank_notifications_path}"
  api_token          = module.setup_expense_tracker_app.bank_notification_token
}

module "setup_expense_tracker_app" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_expense_tracker_app?ref=v-68"

  environment_name      = var.environment_name
  azure_location        = var.azure_location
  owner                 = local.owner
  k8s_oidc_issuer_url   = module.setup_cluster.oidc_issuer_url
  hostname              = data.azurerm_key_vault_secret.dns_zone.value
  tenant_id             = data.azurerm_client_config.current.tenant_id
  azure_subscription_id = var.azure_subscription_id
  k8s_oidc_config       = module.setup_cluster.k8s_oidc_config
  client_log_url        = local.client_log_url
  db_jdbc_url           = module.create_database.jdbc_url
  db_username           = local.db_credentials["expensetracker"].username
  db_password           = local.db_credentials["expensetracker"].password
  twingate_service_key  = module.setup_twingate_access.service_key
}

module "setup_library_app" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_library_app?ref=v-68"

  environment_name      = var.environment_name
  azure_location        = var.azure_location
  openai_api_key        = data.azurerm_key_vault_secret.library_openai_api_key.value
  owner                 = local.owner
  k8s_oidc_issuer_url   = module.setup_cluster.oidc_issuer_url
  hostname              = data.azurerm_key_vault_secret.dns_zone.value
  tenant_id             = data.azurerm_client_config.current.tenant_id
  azure_subscription_id = var.azure_subscription_id
  k8s_oidc_config       = module.setup_cluster.k8s_oidc_config
  client_log_url        = local.client_log_url
  db_jdbc_url           = module.create_database.jdbc_url
  db_username           = local.db_credentials["library"].username
  db_password           = local.db_credentials["library"].password
  twingate_service_key  = module.setup_twingate_access.service_key
}

module "setup_cooking_app" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_cooking_app?ref=v-68"

  environment_name      = var.environment_name
  azure_location        = var.azure_location
  claude_api_key        = data.azurerm_key_vault_secret.cooking_claude_api_key.value
  openai_api_key        = data.azurerm_key_vault_secret.cooking_openai_api_key.value
  owner                 = local.owner
  k8s_oidc_issuer_url   = module.setup_cluster.oidc_issuer_url
  hostname              = data.azurerm_key_vault_secret.dns_zone.value
  tenant_id             = data.azurerm_client_config.current.tenant_id
  azure_subscription_id = var.azure_subscription_id
  k8s_oidc_config       = module.setup_cluster.k8s_oidc_config
  client_log_url        = local.client_log_url
  db_jdbc_url           = module.create_database.jdbc_url
  db_username           = local.db_credentials["cooking"].username
  db_password           = local.db_credentials["cooking"].password
  twingate_service_key  = module.setup_twingate_access.service_key
}

# module "setup_party_app" {
#   source                     = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_party_app?ref=v-68"
#   environment_name           = var.environment_name
#   azure_location             = var.azure_location
#   owner                      = local.owner
#   k8s_oidc_issuer_url        = module.setup_cluster.oidc_issuer_url
#   hostname                   = data.azurerm_key_vault_secret.dns_zone.value
#   tenant_id                  = data.azurerm_client_config.current.tenant_id
#   azure_subscription_id      = var.azure_subscription_id
#   k8s_oidc_config            = module.setup_cluster.k8s_oidc_config
#   client_log_url             = local.client_log_url
#   twingate_service_key       = module.setup_twingate_access.service_key
# }
