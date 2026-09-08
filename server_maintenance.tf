locals {
  server_maintenance_repository = "p07"
}

resource "github_actions_secret" "server_maintenance_twingate_service_key" {
  repository  = local.server_maintenance_repository
  secret_name = "TWINGATE_SERVICE_KEY"
  value       = module.setup_twingate_access.service_key
}

resource "github_actions_secret" "server_maintenance_ssh_host" {
  repository  = local.server_maintenance_repository
  secret_name = "SERVER_SSH_HOST"
  value       = module.provision_server.ipv4_address
}

resource "github_actions_secret" "server_maintenance_ssh_port" {
  repository  = local.server_maintenance_repository
  secret_name = "SERVER_SSH_PORT"
  value       = tostring(module.provision_server.ssh_port)
}

resource "github_actions_secret" "server_maintenance_ssh_user" {
  repository  = local.server_maintenance_repository
  secret_name = "SERVER_SSH_USER"
  value       = module.provision_server.username
}

resource "github_actions_secret" "server_maintenance_ssh_private_key" {
  repository  = local.server_maintenance_repository
  secret_name = "SERVER_SSH_PRIVATE_KEY"
  value       = module.provision_server.ssh_private_key
}
