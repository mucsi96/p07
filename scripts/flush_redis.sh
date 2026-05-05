#!/bin/bash
# Connects to prod Redis via port-forward and runs FLUSHDB.
set -euo pipefail

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}
LOCAL_PORT=6379

if ! command -v az >/dev/null 2>&1; then
  echo "az CLI is required but not found in PATH" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH" >&2
  exit 1
fi

if ! command -v redis-cli >/dev/null 2>&1; then
  echo "redis-cli is required but not found in PATH" >&2
  exit 1
fi

kubeconfig_file="$(mktemp)"
trap 'rm -f "$kubeconfig_file"; [ -n "${port_forward_pid:-}" ] && kill "$port_forward_pid" 2>/dev/null || true' EXIT

az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "k8s-config" \
  --query value \
  --output tsv \
  > "$kubeconfig_file"

echo "Looking up Redis pod using selector app=redis in namespace redis" >&2
pod_name=$(kubectl --kubeconfig "$kubeconfig_file" -n "redis" get pod -l "app=redis" -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$pod_name" ]]; then
  echo "No pods found for selector app=redis in namespace redis" >&2
  exit 1
fi

echo "Starting port-forward to pod $pod_name on port $LOCAL_PORT" >&2
kubectl --kubeconfig "$kubeconfig_file" -n "redis" port-forward "pod/$pod_name" "$LOCAL_PORT:6379" &
port_forward_pid=$!

sleep 2

if ! kill -0 "$port_forward_pid" 2>/dev/null; then
  echo "Port-forward failed to start" >&2
  exit 1
fi

redis_password=$(kubectl --kubeconfig "$kubeconfig_file" -n "redis" get secret redis -o jsonpath='{.data.password}' | base64 -d)

echo "Running FLUSHDB on prod Redis..." >&2
redis-cli -p "$LOCAL_PORT" -a "$redis_password" FLUSHDB

echo "FLUSHDB completed successfully." >&2
