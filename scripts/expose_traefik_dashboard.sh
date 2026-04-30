#!/bin/bash
# Fetches kubeconfig from Azure Key Vault and port-forwards Traefik pod port.
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

echo "Looking up Traefik pod using selector app.kubernetes.io/name=traefik in namespace traefik" >&2
pod_name=$(kubectl --kubeconfig "$kubeconfig_file" -n "traefik" get pod -l "app.kubernetes.io/name=traefik" -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$pod_name" ]]; then
  echo "No pods found for selector app.kubernetes.io/name=traefik in namespace traefik" >&2
  exit 1
fi

echo "Forwarding pod $pod_name port traefik to localhost:8080" >&2
echo "Traefik dashboard should be available at http://localhost:8080/dashboard/" >&2
echo "Press Ctrl+C to stop port-forwarding" >&2
kubectl --kubeconfig "$kubeconfig_file" -n "traefik" port-forward "pod/$pod_name" "8080:traefik"
