#!/bin/bash

set -euo pipefail

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}
REFRESH_TOKEN_SECRET=${NETCUP_REFRESH_TOKEN_SECRET:-netcup-refresh-token}
SERVER_ID_SECRET=${NETCUP_SERVER_ID_SECRET:-netcup-server-id}
CLIENT_ID=scp
API_URL=https://www.servercontrolpanel.de/scp-core
TOKEN_URL=https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/token
TASK_TIMEOUT_SECONDS=${NETCUP_TASK_TIMEOUT_SECONDS:-300}
POLL_INTERVAL_SECONDS=${NETCUP_POLL_INTERVAL_SECONDS:-5}
assume_yes=false
server_may_be_off=false

usage() {
  cat <<'EOF'
Usage: restart_server.sh [--yes]

Gracefully shuts down and starts the Netcup server configured in Azure Key
Vault. Use --yes to skip the interactive confirmation.

Environment variables:
  AZURE_KEYVAULT_NAME          Key Vault name (default: p07)
  NETCUP_SERVER_ID             Override the server ID stored in Key Vault
  NETCUP_TASK_TIMEOUT_SECONDS  Task timeout (default: 300)
  NETCUP_POLL_INTERVAL_SECONDS Poll interval (default: 5)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      assume_yes=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for command in az curl jq; do
  command -v "$command" >/dev/null || {
    echo "Error: '$command' is required." >&2
    exit 1
  }
done

[[ "$TASK_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
  echo "NETCUP_TASK_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 1
}
[[ "$POLL_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
  echo "NETCUP_POLL_INTERVAL_SECONDS must be a positive integer." >&2
  exit 1
}

az account show --output none

refresh_token=$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$REFRESH_TOKEN_SECRET" \
  --query value \
  --output tsv)
server_id=${NETCUP_SERVER_ID:-$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$SERVER_ID_SECRET" \
  --query value \
  --output tsv)}

[[ "$server_id" =~ ^[0-9]+$ ]] || {
  echo "Netcup server ID must be numeric." >&2
  exit 1
}

access_token=
token_refresh_at=0

refresh_access_token() {
  local response expires_in rotated_refresh_token refresh_after

  response=$(printf '%s' "$refresh_token" | curl \
    --fail-with-body --silent --show-error \
    --connect-timeout 10 --max-time 30 \
    --request POST "$TOKEN_URL" \
    --data-urlencode 'grant_type=refresh_token' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode 'refresh_token@-')

  access_token=$(jq -er '.access_token | select(type == "string" and length > 0)' <<<"$response")
  expires_in=$(jq -er '.expires_in | numbers | floor' <<<"$response")
  rotated_refresh_token=$(jq -r '.refresh_token // ""' <<<"$response")

  if [[ -n "$rotated_refresh_token" && "$rotated_refresh_token" != "$refresh_token" ]]; then
    refresh_token=$rotated_refresh_token
    az keyvault secret set \
      --vault-name "$VAULT_NAME" \
      --name "$REFRESH_TOKEN_SECRET" \
      --value "$refresh_token" \
      --output none
  fi

  refresh_after=$((expires_in > 60 ? expires_in - 30 : expires_in / 2))
  token_refresh_at=$(($(date +%s) + refresh_after))
}

ensure_access_token() {
  if [[ -z "$access_token" || $(date +%s) -ge $token_refresh_at ]]; then
    refresh_access_token
  fi
}

api_request() {
  local method=$1
  local path=$2
  local body=${3:-}
  local header_file response
  local -a args

  ensure_access_token
  header_file=$(mktemp)
  chmod 600 "$header_file"
  printf 'Authorization: Bearer %s\n' "$access_token" >"$header_file"

  args=(
    --fail-with-body --silent --show-error
    --connect-timeout 10 --max-time 30
    --request "$method"
    --header 'Accept: application/json'
    --header "@$header_file"
  )
  if [[ -n "$body" ]]; then
    args+=(
      --header 'Content-Type: application/merge-patch+json'
      --header 'Prefer: error-i18n'
      --data-binary "$body"
    )
  fi

  if ! response=$(curl "${args[@]}" "$API_URL$path"); then
    rm -f "$header_file"
    [[ -z "$response" ]] || printf '%s\n' "$response" >&2
    return 1
  fi
  rm -f "$header_file"
  API_RESPONSE=$response
}

wait_for_task() {
  local uuid=$1
  local deadline state

  deadline=$(($(date +%s) + TASK_TIMEOUT_SECONDS))
  while (( $(date +%s) < deadline )); do
    if ! api_request GET "/api/v1/tasks/$uuid"; then
      echo "Unable to read Netcup task $uuid; retrying." >&2
      sleep "$POLL_INTERVAL_SECONDS"
      continue
    fi

    state=$(jq -er '.state' <<<"$API_RESPONSE")
    printf 'Task %s: %s\n' "$uuid" "$state"
    case "$state" in
      FINISHED)
        return 0
        ;;
      ERROR|CANCELED)
        jq . <<<"$API_RESPONSE" >&2
        return 1
        ;;
      PENDING|RUNNING|WAITING_FOR_CANCEL|ROLLBACK)
        ;;
      *)
        echo "Netcup task $uuid returned unknown state: $state" >&2
        return 1
        ;;
    esac
    sleep "$POLL_INTERVAL_SECONDS"
  done

  echo "Timed out waiting for Netcup task $uuid." >&2
  return 1
}

change_server_state() {
  local state=$1
  local response uuid

  api_request PATCH "/api/v1/servers/$server_id" "{\"state\":\"$state\"}"
  response=$API_RESPONSE
  uuid=$(jq -er '.uuid // .taskInfo.uuid' <<<"$response")
  wait_for_task "$uuid"
}

warn_if_server_may_be_off() {
  if [[ "$server_may_be_off" == true ]]; then
    echo "WARNING: The script exited after shutdown was requested but before startup was confirmed." >&2
    echo "Check server $server_id in the Netcup SCP before running the script again." >&2
  fi
}
trap warn_if_server_may_be_off EXIT

api_request GET "/api/v1/servers/$server_id"
server_name=$(jq -er '.hostname // .name' <<<"$API_RESPONSE")
server_state=$(jq -er '.serverLiveInfo.state' <<<"$API_RESPONSE")

case "$server_state" in
  RUNNING)
    ;;
  SHUTOFF)
    echo "Server $server_name ($server_id) is already shut off; only startup will be requested."
    ;;
  *)
    echo "Server $server_name ($server_id) is in state $server_state; refusing to restart it." >&2
    exit 1
    ;;
esac

if [[ "$assume_yes" != true ]]; then
  read -r -p "Gracefully restart Netcup server $server_name ($server_id)? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || {
    echo "Restart cancelled."
    exit 0
  }
fi

if [[ "$server_state" == "RUNNING" ]]; then
  echo "Requesting graceful ACPI shutdown of $server_name ($server_id)..."
  server_may_be_off=true
  change_server_state OFF
fi

echo "Starting $server_name ($server_id)..."
server_may_be_off=true
change_server_state ON
server_may_be_off=false

api_request GET "/api/v1/servers/$server_id"
server_state=$(jq -er '.serverLiveInfo.state' <<<"$API_RESPONSE")
if [[ "$server_state" != "RUNNING" ]]; then
  echo "Startup task finished, but the server reports state $server_state." >&2
  exit 1
fi

echo "Server $server_name ($server_id) is running."
