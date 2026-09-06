#!/bin/bash

set -euo pipefail

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}
CONTEXT_NAME=${KUBE_CONTEXT_NAME:-$VAULT_NAME}
KUBE_DIR=${HOME:?HOME must be set}/.kube
DEFAULT_KUBECONFIG=$KUBE_DIR/config

umask 077
mkdir -p "$KUBE_DIR"

downloaded_config=$(mktemp)
merged_config=$(mktemp "$KUBE_DIR/config.XXXXXX")
trap 'rm -f "$downloaded_config" "$merged_config"' EXIT

az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name k8s-oidc-config \
  --query value \
  --output tsv > "$downloaded_config"

source_context=$(kubectl config current-context --kubeconfig "$downloaded_config")
if [ "$source_context" != "$CONTEXT_NAME" ]; then
  kubectl config rename-context \
    --kubeconfig "$downloaded_config" \
    "$source_context" \
    "$CONTEXT_NAME" > /dev/null
fi

if [ -f "$DEFAULT_KUBECONFIG" ]; then
  KUBECONFIG="$downloaded_config:$DEFAULT_KUBECONFIG" \
    kubectl config view --raw --flatten > "$merged_config"
else
  kubectl config view \
    --kubeconfig "$downloaded_config" \
    --raw \
    --flatten > "$merged_config"
fi

mv "$merged_config" "$DEFAULT_KUBECONFIG"

unset KUBECONFIG
kubectl config use-context "$CONTEXT_NAME"
echo "Kubeconfig merged into $DEFAULT_KUBECONFIG; context '$CONTEXT_NAME' is active."
kubectl get nodes
