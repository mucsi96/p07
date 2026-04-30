resource "azurerm_key_vault_secret" "host" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "host"
  value        = module.provision_hetzner_server.ipv4_address
}

resource "azurerm_key_vault_secret" "ssh_user_name" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "ssh-user-name"
  value        = module.provision_hetzner_server.username
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "ssh-private-key"
  value        = module.setup_cluster.ssh_private_key
}

resource "azurerm_key_vault_secret" "ssh_port" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "ssh-port"
  value        = module.setup_cluster.ssh_port
}

resource "azurerm_key_vault_secret" "user_password" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "user-password"
  value        = module.setup_cluster.user_password
}

resource "azurerm_key_vault_secret" "issuer" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "issuer"
  value        = module.setup_cluster.oidc_issuer_url
}

resource "azurerm_key_vault_secret" "tenant_id" {
  key_vault_id = data.azurerm_key_vault.kv.id
  name         = "tenant-id"
  value        = data.azurerm_client_config.current.tenant_id
}
