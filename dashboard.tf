

output "dashboard_url" {
  value = "https://${nonsensitive(local.observatory_hostname)}"
}
