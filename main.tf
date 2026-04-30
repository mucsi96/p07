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
      version = "5.18.0"
    }

    twingate = {
      source  = "Twingate/twingate"
      version = "4.1.1"
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

data "azurerm_key_vault_secret" "letsencrypt_email" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "letsencrypt-email"
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

data "azurerm_key_vault_secret" "cloudflare_team_domain" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "cloudflare-team-domain"
}

data "azurerm_key_vault_secret" "authorized_as" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "authorized-as"
}

data "azurerm_key_vault_secret" "twingate_api_token" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "twingate-api-token"
}

data "azurerm_key_vault_secret" "twingate_network" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "twingate-network"
}

data "azurerm_key_vault_secret" "github_token" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "github-token"
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

provider "twingate" {
  api_token = data.azurerm_key_vault_secret.twingate_api_token.value
  network   = data.azurerm_key_vault_secret.twingate_network.value
}

provider "github" {
  owner = "mucsi96"
  token = data.azurerm_key_vault_secret.github_token.value
}

module "provision_hetzner_server" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/provision_hetzner_server?ref=main"

  server_name = var.environment_name
  server_type = "cx42"
  location    = var.hetzner_location

  labels = {
    environment = var.environment_name
  }
}

module "setup_cluster" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_cluster?ref=main"

  host                  = module.provision_hetzner_server.ipv4_address
  initial_port          = module.provision_hetzner_server.ssh_port
  username              = module.provision_hetzner_server.username
  initial_password      = module.provision_hetzner_server.initial_password
  azure_key_vault_name  = data.azurerm_key_vault.kv.name
  environment_name      = var.environment_name
  azure_subscription_id = var.azure_subscription_id
  storage_account_name  = var.storage_account_name
  azure_tenant_id       = data.azurerm_client_config.current.tenant_id
}

module "setup_ingress_controller" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_ingress_controller?ref=main"

  environment_name       = var.environment_name
  subscription_id        = var.azure_subscription_id
  dns_zone               = data.azurerm_key_vault_secret.dns_zone.value
  traefik_chart_version  = "39.0.8"  # https://github.com/traefik/traefik-helm-chart/releases
  traefik_version        = "v3.6.14" # https://github.com/traefik/traefik/releases
  letsencrypt_email      = data.azurerm_key_vault_secret.letsencrypt_email.value
  cloudflare_api_token   = data.azurerm_key_vault_secret.cloudflare_api_token.value
  cloudflare_account_id  = data.azurerm_key_vault_secret.cloudflare_account_id.value
  cloudflare_zone_id     = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  cloudflare_team_domain = data.azurerm_key_vault_secret.cloudflare_team_domain.value
  authorized_as          = data.azurerm_key_vault_secret.authorized_as.value
  depends_on             = [module.setup_cluster]
}

module "setup_twingate" {
  source = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_twingate?ref=main"

  environment_name   = var.environment_name
  twingate_network   = data.azurerm_key_vault_secret.twingate_network.value
  twingate_api_token = data.azurerm_key_vault_secret.twingate_api_token.value
  k8s_host           = module.provision_hetzner_server.ipv4_address
  depends_on         = [module.setup_cluster]
}
