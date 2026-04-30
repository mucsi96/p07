#!/usr/bin/env bash
set -euo pipefail

SOURCE_VAULT="p06"
TARGET_VAULT="p07"

SECRETS=(
  "dns-zone"
  "letsencrypt-email"
  "cloudflare-zone-id"
  "cloudflare-account-id"
  "cloudflare-api-token"
  "cloudflare-team-domain"
  "authorized-as"
  "github-token"
)

for secret in "${SECRETS[@]}"; do
  value=$(az keyvault secret show --vault-name "$SOURCE_VAULT" --name "$secret" --query value --output tsv)
  az keyvault secret set --vault-name "$TARGET_VAULT" --name "$secret" --value "$value" --output none
  echo "Copied: $secret"
done

echo "Done."
