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

data "azurerm_key_vault_secret" "cloudflare_account_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "cloudflare-account-id"
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

locals {
  k8s_dashboard_hostname = "dashboard.${data.azurerm_key_vault_secret.dns_zone.value}"
  grafana_hostname       = "grafana.${data.azurerm_key_vault_secret.dns_zone.value}"
  prometheus_hostname    = "prometheus.${data.azurerm_key_vault_secret.dns_zone.value}"

  module_source_base = "git::https://github.com/mucsi96/k8s-modules.git//modules"
  module_source_ref  = "v-25"

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

provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

provider "cloudflare" {
  api_token = data.azurerm_key_vault_secret.cloudflare_api_token.value
}

provider "github" {
  owner = "mucsi96"
  token = data.azurerm_key_vault_secret.github_token.value
}

module "provision_hetzner_server" {
  source = "${local.module_source_base}/provision_hetzner_server?ref=${local.module_source_ref}"

  server_name = var.environment_name
  server_type = "cx43"
  location    = var.hetzner_location

  labels = {
    environment = var.environment_name
  }
}

module "register_cluster_apiserver_oidc_app" {
  source = "${local.module_source_base}/register_webapp?ref=${local.module_source_ref}"

  display_name  = "Headlamp - ${var.environment_name}"
  owner         = local.owner
  redirect_uris = ["https://${local.k8s_dashboard_hostname}/oauth2/callback"]
}

module "setup_cluster" {
  source = "${local.module_source_base}/setup_cluster?ref=${local.module_source_ref}"

  host                  = module.provision_hetzner_server.ipv4_address
  initial_port          = module.provision_hetzner_server.ssh_port
  username              = module.provision_hetzner_server.username
  initial_password      = module.provision_hetzner_server.initial_password
  azure_key_vault_name  = data.azurerm_key_vault.kv.name
  environment_name      = var.environment_name
  azure_subscription_id = var.azure_subscription_id
  storage_account_name  = var.storage_account_name
  azure_tenant_id          = data.azurerm_client_config.current.tenant_id
  local_python_interpreter = abspath("${path.root}/.venv/bin/python3")

  apiserver_oidc = {
    issuer_url = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
    client_id  = module.register_cluster_apiserver_oidc_app.client_id
  }
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
  traefik_chart_version      = "40.0.0"  #https://github.com/traefik/traefik-helm-chart/releases
  traefik_version            = "v3.7.0"  #https://github.com/traefik/traefik/releases
  cloudflare_api_token       = data.azurerm_key_vault_secret.cloudflare_api_token.value
  cloudflare_account_id      = data.azurerm_key_vault_secret.cloudflare_account_id.value
  cloudflare_zone_id         = data.azurerm_key_vault_secret.cloudflare_zone_id.value
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
  source                     = "${local.module_source_base}/setup_k8s_dashboard?ref=${local.module_source_ref}"

  hostname                   = local.k8s_dashboard_hostname
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  client_id                  = module.register_cluster_apiserver_oidc_app.client_id
  client_secret              = module.register_cluster_apiserver_oidc_app.client_secret
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

module "create_database" {
  source        = "${local.module_source_base}/create_postgres_database?ref=${local.module_source_ref}"
  k8s_name      = "postgres1"
  k8s_namespace = module.create_database_namespace.k8s_namespace
  db_name       = "postgres1"
}

locals {
  owner = data.azurerm_client_config.current.object_id
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
  source                              = "${local.module_source_base}/setup_prometheus_operator?ref=${local.module_source_ref}"

  grafana_hostname                    = local.grafana_hostname
  prometheus_hostname                 = local.prometheus_hostname
  tenant_id                           = data.azurerm_client_config.current.tenant_id
  grafana_client_id                   = module.register_grafana_dashboard.client_id
  grafana_client_secret               = module.register_grafana_dashboard.client_secret
  prometheus_client_id                = module.register_prometheus_dashboard.client_id
  prometheus_client_secret            = module.register_prometheus_dashboard.client_secret
  valid_email                         = data.azurerm_key_vault_secret.letsencrypt_email.value
  kube_prometheus_stack_chart_version = "84.5.0"  #https://github.com/prometheus-community/helm-charts/releases?q=kube-prometheus-stack
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
  db_username                = module.create_database.username
  db_password                = module.create_database.password
  wait_for                   = module.setup_ingress_controller.traefik_ready

  azure_storage_account_resource_group_name = "ibari"
  azure_storage_account_name                = "ibari"
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
  db_jdbc_url                = module.create_database.jdbc_url
  db_username                = module.create_database.username
  db_password                = module.create_database.password
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
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  azure_subscription_id      = var.azure_subscription_id
  db_jdbc_url                = module.create_database.jdbc_url
  db_username                = module.create_database.username
  db_password                = module.create_database.password
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
  db_jdbc_url                = module.create_database.jdbc_url
  db_username                = module.create_database.username
  db_password                = module.create_database.password
  wait_for                   = module.setup_ingress_controller.traefik_ready
}
