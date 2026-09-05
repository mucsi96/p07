#!/usr/bin/env bash
set -euo pipefail

environment_name="${1:-p07}"

copy_app_secrets() {
  local app_name="$1"
  shift
  local secrets=("$@")
  local source_vault="${environment_name}-${app_name}"
  local value
  local master_secret_name

  echo "Copying $app_name secrets from $source_vault to $environment_name..."
  for secret in "${secrets[@]}"; do
    value=$(az keyvault secret show --vault-name "$source_vault" --name "$secret" --query value --output tsv)
    master_secret_name="${app_name}-${secret}"
    az keyvault secret set --vault-name "$environment_name" --name "$master_secret_name" --value "$value" --output none
    echo "  Copied: $secret -> $master_secret_name"
  done
}

copy_app_secrets "hello" \
  "claude-api-key"

copy_app_secrets "learn-language" \
  "claude-api-key" \
  "eleven-labs-api-key" \
  "google-ai-api-key" \
  "ideogram-api-key" \
  "openai-api-key" \
  "xai-api-key"

copy_app_secrets "training-log" \
  "strava-client-id" \
  "strava-client-secret" \
  "withings-client-id" \
  "withings-client-secret"

copy_app_secrets "library" \
  "openai-api-key"

copy_app_secrets "cooking" \
  "claude-api-key" \
  "openai-api-key"

echo "Done."
