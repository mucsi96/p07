variable "origin_ipv4" {
  description = "Cloudflare origin override. Set this to the old host during migration, then remove it to cut over to Netcup."
  type        = string
  default     = null
}
