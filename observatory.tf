# Application-owned infrastructure; reusable modules remain pinned to v-101.

resource "azurerm_key_vault" "observatory_app" {
  resource_group_name        = var.environment_name
  name                       = "${var.environment_name}-${local.observatory_name}"
  location                   = var.azure_location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
}

resource "azurerm_role_assignment" "observatory_owner_vault" {
  scope                = azurerm_key_vault.observatory_app.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = local.owner
}

locals {
  observatory_deployment_config = {
    k8s-config            = sensitive(azurerm_key_vault_secret.k8s_oidc_config.value)
    hostname              = local.observatory_hostname
    api-client-id         = module.setup_observatory_api.client_id
    forward-auth-config   = jsonencode(module.observatory_forward_auth.deployment_config)
    client-storage-config = jsonencode(module.observatory_client_storage.deployment_config)
  }
}

resource "azurerm_key_vault_secret" "observatory_deployment" {
  for_each     = nonsensitive(toset(keys(local.observatory_deployment_config)))
  key_vault_id = azurerm_key_vault.observatory_app.id
  name         = each.key
  value        = local.observatory_deployment_config[each.key]
  depends_on   = [azurerm_role_assignment.observatory_owner_vault]
}

resource "azurerm_role_assignment" "observatory_deploy_config" {
  for_each             = azurerm_key_vault_secret.observatory_deployment
  scope                = each.value.resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_service_principal.observatory_github_deploy.object_id
}

resource "azuread_application" "observatory_github_deploy" {
  display_name     = "GitHub Actions deploy - ${var.environment_name} - ${local.observatory_name}"
  sign_in_audience = "AzureADMyOrg"
  owners           = [local.owner]
}

resource "azuread_service_principal" "observatory_github_deploy" {
  client_id = azuread_application.observatory_github_deploy.client_id
  owners    = [local.owner]
}

data "github_user" "observatory_repository_owner" {
  username = "mucsi96"
}

data "github_repository" "observatory_app" {
  full_name = "mucsi96/observatory-app"
}

# Match the immutable OIDC subjects used by the other application deployers.
resource "azuread_application_federated_identity_credential" "observatory_github_deploy" {
  application_id = azuread_application.observatory_github_deploy.id
  display_name   = "github-actions-k8s-deploy"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:mucsi96@${data.github_user.observatory_repository_owner.id}/observatory-app@${data.github_repository.observatory_app.repo_id}:ref:refs/heads/main"
}

resource "kubernetes_role_v1" "observatory_deploy" {
  metadata {
    name      = "observatory-deploy"
    namespace = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  }
  rule {
    api_groups = ["", "apps", "gateway.networking.k8s.io"]
    resources  = ["deployments", "replicasets", "pods", "services", "serviceaccounts", "secrets", "configmaps", "httproutes"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["traefik.io"]
    resources  = ["middlewares", "traefikservices"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "observatory_deploy" {
  metadata {
    name      = "observatory-deploy"
    namespace = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.observatory_deploy.metadata[0].name
  }
  subject {
    kind      = "User"
    name      = azuread_service_principal.observatory_github_deploy.object_id
    api_group = "rbac.authorization.k8s.io"
  }
}

locals {
  observatory_deploy_secrets = {
    AZURE_CLIENT_ID       = azuread_application.observatory_github_deploy.client_id
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID = var.azure_subscription_id
    AZURE_KEYVAULT_NAME   = azurerm_key_vault.observatory_app.name
    TWINGATE_SERVICE_KEY  = sensitive(module.setup_twingate_access.service_key)
  }
}

resource "github_actions_secret" "observatory_deploy" {
  for_each    = nonsensitive(toset(keys(local.observatory_deploy_secrets)))
  repository  = "observatory-app"
  secret_name = each.key
  value       = local.observatory_deploy_secrets[each.key]
}

resource "github_actions_variable" "observatory_deploy_enabled" {
  repository    = "observatory-app"
  variable_name = "DEPLOY_ENABLED"
  value         = "true"
  depends_on = [
    github_actions_secret.observatory_deploy,
    azuread_application_federated_identity_credential.observatory_github_deploy,
    azurerm_role_assignment.observatory_deploy_config,
    module.observatory_forward_auth,
    kubernetes_role_binding_v1.observatory_deploy,
    kubernetes_role_binding_v1.observatory_reader,
    kubernetes_config_map_v1.observatory_dashboard,
    kubernetes_secret_v1.observatory_github,
  ]
}

locals {
  observatory_name                     = "observatory"
  observatory_api_service_account_name = "observatory-api-workload-identity"
  observatory_apps = concat([
    module.hello_app_base.dashboard_app,
    module.learn_language_app_base.dashboard_app,
    module.training_log_app_base.dashboard_app,
    module.expense_tracker_app_base.dashboard_app,
    module.library_app_base.dashboard_app,
    module.cooking_app_base.dashboard_app,
    module.backup_app_base.dashboard_app,
    {
      name       = "p07"
      namespace  = ""
      repository = "mucsi96/p07"
      url        = "https://github.com/mucsi96/p07"
    },
    {
      name       = "k8s-modules"
      namespace  = ""
      repository = "mucsi96/k8s-modules"
      url        = "https://github.com/mucsi96/k8s-modules"
    },
    ], [{
      name       = "Observatory"
      namespace  = local.observatory_name
      repository = "mucsi96/observatory-app"
      url        = "https://${nonsensitive(local.observatory_hostname)}"
  }])
}

resource "terraform_data" "observatory_ready" { input = module.setup_ingress_controller.ingress_controller_ready }

module "observatory_client_storage" {
  source              = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_static_website?ref=v-101"
  name                = "${var.environment_name}obsweb${substr(sha256(var.azure_subscription_id), 0, 8)}"
  resource_group_name = var.environment_name
  location            = var.azure_location
  app_origin          = "https://${local.observatory_hostname}"
  deploy_principal_id = azuread_service_principal.observatory_github_deploy.object_id
}

resource "kubernetes_namespace_v1" "observatory_dashboard" {
  metadata { name = local.observatory_name }
  depends_on = [terraform_data.observatory_ready]
}

removed {
  from = module.setup_app_dashboard.kubernetes_service_account_v1.dashboard
  lifecycle { destroy = false }
}

# Deployment readiness and images only. No secrets, logs, exec, or write access.
resource "kubernetes_role_v1" "observatory_reader" {
  for_each = toset([for app in local.observatory_apps : app.namespace if app.namespace != ""])
  metadata {
    name      = "observatory-reader"
    namespace = each.value
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["list"]
  }
  depends_on = [kubernetes_namespace_v1.observatory_dashboard]
}

resource "kubernetes_role_binding_v1" "observatory_reader" {
  for_each = kubernetes_role_v1.observatory_reader
  metadata {
    name      = "observatory-reader"
    namespace = each.value.metadata[0].namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = each.value.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.observatory_api_service_account_name
    namespace = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "observatory_dashboard" {
  metadata {
    name      = local.observatory_name
    namespace = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  }
  data = { "config.json" = jsonencode({
    environment = var.environment_name
    apps        = local.observatory_apps
    auth = {
      issuer      = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
      apiClientId = module.setup_observatory_api.client_id
    }
  }) }
}

resource "kubernetes_secret_v1" "observatory_github" {
  metadata {
    name      = "observatory-github"
    namespace = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  }
  data = { token = sensitive(data.azurerm_key_vault_secret.github_token.value) }
}

// Workloads are now owned by observatory-app's deployment pipeline. Preserve the
// live resources during the handoff; Helm adopts the same names.
removed {
  from = module.setup_app_dashboard.kubernetes_deployment_v1.dashboard
  lifecycle { destroy = false }
}

removed {
  from = module.setup_app_dashboard.kubernetes_service_v1.dashboard
  lifecycle { destroy = false }
}

module "setup_observatory_api" {
  source                        = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_api?ref=v-101"
  owner                         = local.owner
  display_name                  = "Observatory API"
  roles                         = ["readApps"]
  k8s_oidc_issuer_url           = module.setup_cluster.oidc_issuer_url
  k8s_service_account_namespace = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  k8s_service_account_name      = local.observatory_api_service_account_name
}

module "setup_observatory_web" {
  source        = "git::https://github.com/mucsi96/k8s-modules.git//modules/register_web?ref=v-101"
  owner         = local.owner
  display_name  = "Observatory Web"
  redirect_uris = ["https://${local.observatory_hostname}/oauth2/callback"]
  api_access = {
    application_id = module.setup_observatory_api.application_id
    client_id      = module.setup_observatory_api.client_id
    scope_id       = module.setup_observatory_api.scope_id
  }
}

module "observatory_forward_auth" {
  source              = "git::https://github.com/mucsi96/k8s-modules.git//modules/setup_app_forwardauth?ref=v-101"
  name                = local.observatory_name
  namespace           = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  hostname            = local.observatory_hostname
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client_id           = module.setup_observatory_web.client_id
  client_secret       = module.setup_observatory_web.client_secret
  api_client_id       = module.setup_observatory_api.client_id
  trusted_proxy_cidrs = nonsensitive(sensitive(local.app_forward_auth).trusted_proxy_cidrs)
  session_redis       = sensitive(local.app_forward_auth).session_redis
  gateway_parent_ref  = sensitive(local.app_forward_auth).gateway_parent_ref
}

# Charts own application routes; the API also validates JWTs, scope and roles.
resource "kubernetes_network_policy_v1" "observatory_dashboard" {
  metadata {
    name      = local.observatory_name
    namespace = kubernetes_namespace_v1.observatory_dashboard.metadata[0].name
  }
  spec {
    pod_selector {
      match_expressions {
        key      = "app"
        operator = "In"
        values   = [local.observatory_name, "${local.observatory_name}-client"]
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = module.setup_ingress_controller.ingress_controller_namespace }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "traefik" }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }
  }
}
