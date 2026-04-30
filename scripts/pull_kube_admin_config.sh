#!/bin/bash

set -euo pipefail

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}

mkdir -p .kube
az keyvault secret show --vault-name "$VAULT_NAME" --name k8s-config --query value --output tsv > .kube/admin-config
