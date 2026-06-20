terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.14.0"
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

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.6"
    }

    acme = {
      source  = "vancluever/acme"
      version = ">= 2.28.2"
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

    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.48.0"
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

  required_version = ">= 1.2"
}

provider "random" {}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

provider "azuread" {}

provider "ansible" {}

data "azurerm_client_config" "current" {}

data "azurerm_key_vault" "kv" {
  resource_group_name = var.environment_name
  name                = var.environment_name
}

data "azurerm_key_vault_secret" "hcloud_token" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "hcloud-token"
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

locals {
  k8s_dashboard_hostname = "dashboard.${data.azurerm_key_vault_secret.dns_zone.value}"
  grafana_hostname       = "grafana.${data.azurerm_key_vault_secret.dns_zone.value}"
  prometheus_hostname    = "prometheus.${data.azurerm_key_vault_secret.dns_zone.value}"
  cloudbeaver_hostname   = "db.${data.azurerm_key_vault_secret.dns_zone.value}"
  faro_hostname          = "faro.${data.azurerm_key_vault_secret.dns_zone.value}"
  # /collect is the path the Faro Web SDK POSTs telemetry to. Stored verbatim
  # in each app's Key Vault so the SPA can use it without further URL juggling.
  client_log_url = "https://${local.faro_hostname}/collect"

  module_source_base = "git::https://github.com/mucsi96/k8s-modules.git//modules"
  module_source_ref  = "v-41"

  oauth2_proxy_chart_version = "10.4.3"  #https://github.com/oauth2-proxy/manifests/releases
  oauth2_proxy_image_version = "v7.15.2" #https://github.com/oauth2-proxy/oauth2-proxy/releases
}

provider "hcloud" {
  token = data.azurerm_key_vault_secret.hcloud_token.value
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

# Used in place of hashicorp/kubernetes's kubernetes_manifest for CRDs (Traefik
# IngressRoute / Middleware). kubernetes_manifest opens a REST client at plan
# time and breaks the from-scratch apply because the cluster does not exist
# yet; kubectl_manifest defers the connection to apply time.
provider "kubectl" {
  host                   = module.setup_cluster.k8s_host
  client_certificate     = module.setup_cluster.k8s_client_certificate
  client_key             = module.setup_cluster.k8s_client_key
  cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  load_config_file       = false
}

provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
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

# Created before the server: its connector tokens are baked into the server's
# cloud-init user_data. No depends_on — must NOT order after setup_cluster.
module "setup_twingate_connector" {
  source           = "${local.module_source_base}/setup_twingate_connector?ref=${local.module_source_ref}"
  environment_name = var.environment_name
}

# Needs the server's address/port, so it orders after provision_hetzner_server
# via field references. No depends_on (would cycle with ssh_ready_wait_for).
module "setup_twingate_access" {
  source            = "${local.module_source_base}/setup_twingate_access?ref=${local.module_source_ref}"
  environment_name  = var.environment_name
  remote_network_id = module.setup_twingate_connector.remote_network_id
  k8s_host          = module.provision_hetzner_server.ipv4_address
  ssh_address       = module.provision_hetzner_server.ipv4_address
  ssh_port          = module.provision_hetzner_server.ssh_port
}

module "provision_hetzner_server" {
  source = "${local.module_source_base}/provision_hetzner_server?ref=${local.module_source_ref}"

  server_name            = var.environment_name
  server_type            = "cpx32"
  location               = "nbg1"
  image                  = "ubuntu-26.04"
  username               = "ubuntu"
  https_source_ips       = concat(data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs, data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs)
  twingate_network       = data.azurerm_key_vault_secret.twingate_network.value
  twingate_access_token  = module.setup_twingate_connector.access_token
  twingate_refresh_token = module.setup_twingate_connector.refresh_token
  ssh_ready_wait_for     = module.setup_twingate_access.ssh_resource_id

  labels = {
    environment = var.environment_name
  }
}

module "setup_cluster" {
  source = "${local.module_source_base}/setup_cluster?ref=${local.module_source_ref}"

  host                          = module.provision_hetzner_server.ipv4_address
  ssh_port                      = module.provision_hetzner_server.ssh_port
  username                      = module.provision_hetzner_server.username
  azure_key_vault_name          = data.azurerm_key_vault.kv.name
  environment_name              = var.environment_name
  azure_subscription_id         = var.azure_subscription_id
  storage_account_name          = var.storage_account_name
  azure_tenant_id               = data.azurerm_client_config.current.tenant_id
  owner                         = local.owner
  cluster_monitor_redirect_uris = ["https://${local.k8s_dashboard_hostname}/oauth2/callback"]
  local_python_interpreter      = abspath("${path.root}/.venv/bin/python3")
  wait_for                      = module.provision_hetzner_server.ssh_ready
}

module "create_redis_namespace" {
  source           = "${local.module_source_base}/create_app_namespace?ref=${local.module_source_ref}"
  environment_name = var.environment_name
  k8s_namespace    = "redis"

  k8s_host                   = module.setup_cluster.k8s_host
  k8s_cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  wait_for                   = module.setup_ingress_controller.traefik_ready
}

module "create_redis" {
  source        = "${local.module_source_base}/setup_redis?ref=${local.module_source_ref}"
  k8s_name      = "redis"
  k8s_namespace = module.create_redis_namespace.k8s_namespace
}

module "setup_ingress_controller" {
  source = "${local.module_source_base}/setup_ingress_controller?ref=${local.module_source_ref}"

  environment_name           = var.environment_name
  subscription_id            = var.azure_subscription_id
  dns_zone                   = data.azurerm_key_vault_secret.dns_zone.value
  traefik_chart_version      = "40.0.0" #https://github.com/traefik/traefik-helm-chart/releases
  traefik_version            = "v3.7.0" #https://github.com/traefik/traefik/releases
  cloudflare_zone_id         = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  origin_ipv4                = module.provision_hetzner_server.ipv4_address
  cloudflare_ipv4_cidrs      = data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs
  cloudflare_ipv6_cidrs      = data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs
  authorized_as              = data.azurerm_key_vault_secret.authorized_as.value
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  owner                      = local.owner
  oauth2_proxy_chart_version = local.oauth2_proxy_chart_version
  oauth2_proxy_image_version = local.oauth2_proxy_image_version
  valid_email                = data.azurerm_key_vault_secret.letsencrypt_email.value
  session_redis = {
    connection_url = module.create_redis.connection_url
    password       = module.create_redis.password
  }
}

module "setup_metrics_server" {
  source                       = "${local.module_source_base}/setup_metrics_server?ref=${local.module_source_ref}"
  metrics_server_chart_version = "3.13.0" #https://github.com/kubernetes-sigs/metrics-server/releases
  metrics_server_image_version = "v0.8.1" #https://github.com/kubernetes-sigs/metrics-server/releases
  wait_for                     = module.setup_ingress_controller.traefik_ready
}

module "setup_k8s_dashboard" {
  source = "${local.module_source_base}/setup_k8s_dashboard?ref=${local.module_source_ref}"

  hostname                   = local.k8s_dashboard_hostname
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  client_id                  = module.setup_cluster.cluster_monitor_client_id
  client_secret              = module.setup_cluster.cluster_monitor_client_secret
  valid_email                = data.azurerm_key_vault_secret.letsencrypt_email.value
  headlamp_chart_version     = "0.41.0"  #https://github.com/headlamp-k8s/headlamp/releases
  headlamp_image_version     = "v0.41.0" #https://github.com/headlamp-k8s/headlamp/releases
  oauth2_proxy_chart_version = local.oauth2_proxy_chart_version
  oauth2_proxy_image_version = local.oauth2_proxy_image_version
  session_redis = {
    connection_url = module.create_redis.connection_url
    password       = module.create_redis.password
  }
  wait_for = module.setup_metrics_server.metrics_server_ready
}

module "create_database_namespace" {
  source           = "${local.module_source_base}/create_app_namespace?ref=${local.module_source_ref}"
  environment_name = var.environment_name
  k8s_namespace    = "db"

  k8s_host                   = module.setup_cluster.k8s_host
  k8s_cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  wait_for                   = module.setup_ingress_controller.traefik_ready
}

module "setup_prometheus_operator_crds" {
  source = "${local.module_source_base}/setup_prometheus_operator_crds?ref=${local.module_source_ref}"

  prometheus_operator_crds_chart_version = "28.0.1" #https://github.com/prometheus-community/helm-charts/releases?q=prometheus-operator-crds
  wait_for                               = module.setup_ingress_controller.traefik_ready
}

module "create_database" {
  source        = "${local.module_source_base}/create_postgres_database?ref=${local.module_source_ref}"
  k8s_name      = "postgres1"
  k8s_namespace = module.create_database_namespace.k8s_namespace
  db_name       = "postgres1"

  wait_for = module.setup_prometheus_operator_crds.crds_ready
}

locals {
  owner = data.azurerm_client_config.current.object_id
  db = {
    host     = module.create_database.host
    port     = module.create_database.port
    database = module.create_database.name
    username = module.create_database.username
    password = module.create_database.password
  }
}

module "register_grafana_dashboard" {
  source = "${local.module_source_base}/register_webapp?ref=${local.module_source_ref}"

  display_name  = "Grafana - ${var.environment_name}"
  owner         = local.owner
  redirect_uris = ["https://${local.grafana_hostname}/oauth2/callback"]
}

module "register_prometheus_dashboard" {
  source = "${local.module_source_base}/register_webapp?ref=${local.module_source_ref}"

  display_name  = "Prometheus - ${var.environment_name}"
  owner         = local.owner
  redirect_uris = ["https://${local.prometheus_hostname}/oauth2/callback"]
}

module "setup_prometheus_operator" {
  source = "${local.module_source_base}/setup_prometheus_operator?ref=${local.module_source_ref}"

  grafana_hostname                    = local.grafana_hostname
  prometheus_hostname                 = local.prometheus_hostname
  tenant_id                           = data.azurerm_client_config.current.tenant_id
  grafana_client_id                   = module.register_grafana_dashboard.client_id
  grafana_client_secret               = module.register_grafana_dashboard.client_secret
  prometheus_client_id                = module.register_prometheus_dashboard.client_id
  prometheus_client_secret            = module.register_prometheus_dashboard.client_secret
  valid_email                         = data.azurerm_key_vault_secret.letsencrypt_email.value
  kube_prometheus_stack_chart_version = "84.5.0" #https://github.com/prometheus-community/helm-charts/releases?q=kube-prometheus-stack
  oauth2_proxy_chart_version          = local.oauth2_proxy_chart_version
  oauth2_proxy_image_version          = local.oauth2_proxy_image_version
  session_redis = {
    connection_url = module.create_redis.connection_url
    password       = module.create_redis.password
  }
  database = {
    host           = module.create_database.host
    port           = module.create_database.port
    name           = module.create_database.name
    admin_username = module.create_database.username
    admin_password = module.create_database.password
  }
  wait_for = module.setup_ingress_controller.traefik_ready
}

module "setup_loki" {
  source = "${local.module_source_base}/setup_loki?ref=${local.module_source_ref}"

  loki_chart_version  = "7.0.0" #https://github.com/grafana/loki/blob/main/production/helm/loki/Chart.yaml
  alloy_chart_version = "1.8.1" #https://github.com/grafana/helm-charts/releases?q=alloy
  grafana_namespace   = module.setup_prometheus_operator.namespace
  faro_hostname       = local.faro_hostname
  faro_cors_allowed_origins = [
    "https://hello.${data.azurerm_key_vault_secret.dns_zone.value}",
    "https://language.${data.azurerm_key_vault_secret.dns_zone.value}",
    "https://training.${data.azurerm_key_vault_secret.dns_zone.value}",
    "https://backup.${data.azurerm_key_vault_secret.dns_zone.value}",
  ]
  wait_for = module.setup_prometheus_operator.kube_prometheus_stack_ready
}

module "register_cloudbeaver" {
  source = "${local.module_source_base}/register_webapp?ref=${local.module_source_ref}"

  display_name  = "cloudbeaver - ${var.environment_name}"
  owner         = local.owner
  redirect_uris = ["https://${local.cloudbeaver_hostname}/oauth2/callback"]
}

module "setup_cloudbeaver" {
  source = "${local.module_source_base}/setup_cloudbeaver?ref=${local.module_source_ref}"

  hostname                   = local.cloudbeaver_hostname
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  client_id                  = module.register_cloudbeaver.client_id
  client_secret              = module.register_cloudbeaver.client_secret
  valid_email                = data.azurerm_key_vault_secret.letsencrypt_email.value
  cloudbeaver_image_version  = "26.1.0"  #https://github.com/dbeaver/cloudbeaver/releases
  oauth2_proxy_chart_version = local.oauth2_proxy_chart_version
  oauth2_proxy_image_version = local.oauth2_proxy_image_version
  session_redis = {
    connection_url = module.create_redis.connection_url
    password       = module.create_redis.password
  }
  database = {
    name     = module.create_database.name
    host     = module.create_database.host
    port     = module.create_database.port
    username = module.create_database.username
    password = module.create_database.password
  }
  wait_for = module.setup_ingress_controller.traefik_ready
}

module "setup_backup_app" {
  source                     = "${local.module_source_base}/setup_backup_app?ref=${local.module_source_ref}"
  environment_name           = var.environment_name
  azure_location             = var.azure_location
  owner                      = local.owner
  k8s_host                   = module.setup_cluster.k8s_host
  k8s_cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  k8s_oidc_issuer_url        = module.setup_cluster.oidc_issuer_url
  hostname                   = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id      = var.azure_subscription_id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config            = module.setup_cluster.k8s_oidc_config
  client_log_url             = local.client_log_url
  twingate_service_key       = module.setup_twingate_access.service_key
  wait_for                   = module.setup_ingress_controller.traefik_ready

  azure_storage_account_resource_group_name = "ibari"
  azure_storage_account_name                = "ibari"

  dbs_config = [
    merge(local.db, {
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
    merge(local.db, {
      name            = "Training log"
      schema          = "training_log"
      createPlainDump = true
      excludeTables = [
        "oauth2_authorized_client"
      ]
    }),
    merge(local.db, {
      name   = "Grafana"
      schema = "grafana"
    })
  ]
}

module "setup_learn_language_app" {
  source                     = "${local.module_source_base}/setup_learn_language_app?ref=${local.module_source_ref}"
  environment_name           = var.environment_name
  azure_location             = var.azure_location
  owner                      = local.owner
  k8s_host                   = module.setup_cluster.k8s_host
  k8s_cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  k8s_oidc_issuer_url        = module.setup_cluster.oidc_issuer_url
  hostname                   = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id      = var.azure_subscription_id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config            = module.setup_cluster.k8s_oidc_config
  client_log_url             = local.client_log_url
  db_jdbc_url                = module.create_database.jdbc_url
  db_username                = module.create_database.username
  db_password                = module.create_database.password
  twingate_service_key       = module.setup_twingate_access.service_key
  wait_for                   = module.setup_ingress_controller.traefik_ready
}

module "setup_hello_app" {
  source                     = "${local.module_source_base}/setup_hello_app?ref=${local.module_source_ref}"
  environment_name           = var.environment_name
  azure_location             = var.azure_location
  owner                      = local.owner
  k8s_host                   = module.setup_cluster.k8s_host
  k8s_cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  k8s_oidc_issuer_url        = module.setup_cluster.oidc_issuer_url
  hostname                   = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id      = var.azure_subscription_id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config            = module.setup_cluster.k8s_oidc_config
  client_log_url             = local.client_log_url
  db_jdbc_url                = module.create_database.jdbc_url
  db_username                = module.create_database.username
  db_password                = module.create_database.password
  twingate_service_key       = module.setup_twingate_access.service_key
  wait_for                   = module.setup_ingress_controller.traefik_ready
}

module "setup_training_log_app" {
  source                     = "${local.module_source_base}/setup_training_log_app?ref=${local.module_source_ref}"
  environment_name           = var.environment_name
  azure_location             = var.azure_location
  owner                      = local.owner
  k8s_host                   = module.setup_cluster.k8s_host
  k8s_cluster_ca_certificate = module.setup_cluster.k8s_cluster_ca_certificate
  k8s_oidc_issuer_url        = module.setup_cluster.oidc_issuer_url
  hostname                   = data.azurerm_key_vault_secret.dns_zone.value
  azure_subscription_id      = var.azure_subscription_id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  k8s_oidc_config            = module.setup_cluster.k8s_oidc_config
  client_log_url             = local.client_log_url
  db_jdbc_url                = module.create_database.jdbc_url
  db_username                = module.create_database.username
  db_password                = module.create_database.password
  twingate_service_key       = module.setup_twingate_access.service_key
  wait_for                   = module.setup_ingress_controller.traefik_ready
}
