#!/bin/bash

set -euo pipefail

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--plan-only" ]; }; then
  echo "Usage: $0 [--plan-only]" >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
apps='hello|cooking|library|learn_language|training_log|expense_tracker|backup|observatory'
state_resources=$(terraform state list)
targets=()
while IFS= read -r address; do
  if [[ "$address" =~ ^module\.($apps)_app_base\.azurerm_key_vault\.app_kv$ ]] ||
     [[ "$address" =~ ^module\.($apps)_client_storage\.azurerm_storage_account\.website$ ]] ||
     [[ "$address" == azurerm_key_vault.observatory_app ]]; then
    targets+=("-target=$address")
  fi
done <<< "$state_resources"

if [ "${#targets[@]}" -eq 0 ]; then
  echo "No app vaults or frontend storage accounts found in Terraform state."
  exit 0
fi

# Reuse the existing SSH/provider setup and Terraform plan/apply workflow.
# Terraform also destroys downstream dependents of these targets.
bash scripts/destroy.sh "$@" "${targets[@]}"
