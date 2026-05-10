#!/usr/bin/env bash
set -euo pipefail

copy_secrets() {
  local source_vault="$1"
  local target_vault="$2"
  shift 2
  local secrets=("$@")

  echo "Copying from $source_vault to $target_vault..."
  for secret in "${secrets[@]}"; do
    value=$(az keyvault secret show --vault-name "$source_vault" --name "$secret" --query value --output tsv)
    az keyvault secret set --vault-name "$target_vault" --name "$secret" --value "$value" --output none
    echo "  Copied: $secret"
  done
}

copy_secrets "p06-hello" "p07-hello" \
  "claude-api-key"

copy_secrets "p06-learn-language" "p07-learn-language" \
  "claude-api-key" \
  "eleven-labs-api-key" \
  "google-ai-api-key" \
  "openai-api-key"

copy_secrets "p06-training-log" "p07-training-log" \
  "strava-client-id" \
  "strava-client-secret" \
  "withings-client-id" \
  "withings-client-secret"

echo "Done."
