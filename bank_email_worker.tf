# Application-owned infrastructure; reusable modules remain pinned to v-101.

locals {
  bank_email_worker_bank_email_address = "bank@${sensitive(data.azurerm_key_vault_secret.dns_zone.value)}"
}

# Workers scripts are account-level resources; resolve the account from the
# zone instead of requiring a separate account-id secret.
data "cloudflare_zone" "bank_email_worker_zone" {
  zone_id = data.azurerm_key_vault_secret.cloudflare_zone_id.value
}

# Enables Email Routing on the zone (the email/routing/enable API), which
# provisions the required MX and SPF records at the apex. The proxied wildcard
# A record is unaffected — Email Routing only receives mail, it never serves
# HTTP. Not cloudflare_email_routing_dns: that resource manages *subdomain*
# routing and rejects the zone apex with a 422.
resource "cloudflare_email_routing_settings" "bank_email_worker_email_routing" {
  zone_id = data.azurerm_key_vault_secret.cloudflare_zone_id.value
}

resource "cloudflare_workers_script" "bank_email_worker" {
  account_id         = data.cloudflare_zone.bank_email_worker_zone.account.id
  script_name        = "bank-email-notifications"
  content            = file("${path.module}/workers/bank-email.js")
  main_module        = "worker.js"
  compatibility_date = "2025-01-01"

  bindings = [
    {
      name = "TARGET_URL"
      type = "plain_text"
      text = "https://${local.expense_tracker_hostname}${local.bank_notifications_path}"
    },
    {
      name = "API_TOKEN"
      type = "secret_text"
      text = sensitive(random_password.expense_tracker_bank_notification_token.result)
    }
  ]
}

resource "cloudflare_email_routing_rule" "bank_email_worker_bank_notifications" {
  zone_id  = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  name     = "Bank card notifications to expense tracker"
  enabled  = true
  priority = 0

  matchers = [{
    type  = "literal"
    field = "to"
    value = local.bank_email_worker_bank_email_address
  }]

  actions = [{
    type  = "worker"
    value = [cloudflare_workers_script.bank_email_worker.script_name]
  }]

  depends_on = [cloudflare_email_routing_settings.bank_email_worker_email_routing]
}
