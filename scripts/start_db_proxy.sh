#!/bin/bash
# Fetches kubeconfig from Azure Key Vault and port-forwards PostgreSQL pod port.
set -euo pipefail

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}

if ! command -v az >/dev/null 2>&1; then
  echo "az CLI is required but not found in PATH" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH" >&2
  exit 1
fi

kubeconfig_file="$(mktemp)"
trap 'rm -f "$kubeconfig_file"' EXIT

az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "k8s-config" \
  --query value \
  --output tsv \
  > "$kubeconfig_file"

echo "Looking up PostgreSQL pod using selector app=postgres1 in namespace db" >&2
pod_name=$(kubectl --kubeconfig "$kubeconfig_file" -n "db" get pod -l "app=postgres1" -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$pod_name" ]]; then
  echo "No pods found for selector app=postgres1 in namespace db" >&2
  exit 1
fi

echo "Forwarding pod $pod_name port 5432 to localhost:5432" >&2
echo "PostgreSQL should be available at localhost:5432" >&2
echo "Press Ctrl+C to stop port-forwarding" >&2
kubectl --kubeconfig "$kubeconfig_file" -n "db" port-forward "pod/$pod_name" "5432:5432"
