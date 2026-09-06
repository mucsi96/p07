#!/bin/bash
# Opens psql as the owner of a selected production application schema.
set -euo pipefail
set +x
umask 077

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}
CONTEXT_NAME=${KUBE_CONTEXT_NAME:-$VAULT_NAME}
DB_NAMESPACE=${POSTGRES_NAMESPACE:-db}
DB_SERVICE=${POSTGRES_SERVICE:-postgres1}
DB_NAME=${POSTGRES_DATABASE:-postgres1}
LOCAL_PORT=${POSTGRES_LOCAL_PORT:-15432}

usage() {
  echo "Usage: $0 [app]" >&2
  echo "Run without an app to choose interactively." >&2
}

if (( $# > 1 )); then
  usage
  exit 2
fi

for command_name in az kubectl jq psql; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required but not found in PATH; enter the Nix dev shell first" >&2
    exit 1
  fi
done

if ! [[ "$LOCAL_PORT" =~ ^[0-9]{1,5}$ ]] || (( 10#$LOCAL_PORT < 1 || 10#$LOCAL_PORT > 65535 )); then
  echo "POSTGRES_LOCAL_PORT must be a number between 1 and 65535" >&2
  exit 1
fi
LOCAL_PORT=$((10#$LOCAL_PORT))

configured_context=$(kubectl config get-contexts "$CONTEXT_NAME" -o name 2>/dev/null || true)
if [[ "$configured_context" != "$CONTEXT_NAME" ]]; then
  echo "Kubernetes context '$CONTEXT_NAME' was not found." >&2
  echo "Run scripts/pull_kube_admin_config.sh first or set KUBE_CONTEXT_NAME." >&2
  exit 1
fi

app_rows=(
  $'cooking\tcooking'
  $'expense-tracker\texpensetracker'
  $'grafana\tgrafana'
  $'hello\thello'
  $'learn-language\tlearn_language'
  $'library\tlibrary'
  $'training-log\ttraining_log'
)
selected_row=

if (( $# == 1 )); then
  requested_app=$1
  for row in "${app_rows[@]}"; do
    IFS=$'\t' read -r app schema <<< "$row"
    if [[ "$requested_app" == "$schema" || "$requested_app" == "$app" ]]; then
      selected_row=$row
      break
    fi
  done

  if [[ -z "$selected_row" ]]; then
    echo "Unknown app '$requested_app'. Available schemas:" >&2
    printf '  %s\n' "${app_rows[@]#*$'\t'}" >&2
    exit 2
  fi
else
  if [[ ! -t 0 ]]; then
    usage
    exit 2
  fi

  echo "Production application schemas:"
  for index in "${!app_rows[@]}"; do
    IFS=$'\t' read -r _ schema <<< "${app_rows[$index]}"
    printf '  %d. %s\n' "$((index + 1))" "$schema"
  done

  while true; do
    read -r -p "Select app [1-${#app_rows[@]}]: " selection
    if [[ "$selection" =~ ^[1-9]$ ]] &&
       (( selection >= 1 && selection <= ${#app_rows[@]} )); then
      selected_row=${app_rows[$((selection - 1))]}
      break
    fi
    echo "Enter a number from 1 to ${#app_rows[@]}." >&2
  done
fi

IFS=$'\t' read -r app schema <<< "$selected_row"
if ! [[ "$schema" =~ ^[a-z_][a-z0-9_]{0,62}$ ]]; then
  echo "Refusing invalid schema name '$schema'" >&2
  exit 1
fi

if [[ "$app" == grafana ]]; then
  # Grafana still consumes this runtime Secret; it has no app Key Vault.
  secret_json=$(kubectl --context "$CONTEXT_NAME" -n monitoring get secret grafana-database -o json)
  username=$(jq -er '.data.GRAFANA_USER // empty | @base64d' <<< "$secret_json")
  password=$(jq -er '.data.GRAFANA_PASSWORD // empty | @base64d' <<< "$secret_json")
else
  app_vault="$VAULT_NAME-$app"
  username=$(az keyvault secret show --vault-name "$app_vault" --name db-username --query value --output tsv --only-show-errors)
  password=$(az keyvault secret show --vault-name "$app_vault" --name db-password --query value --output tsv --only-show-errors)
fi

if [[ "$username" != "$schema" || -z "$password" || "$password" == *$'\n'* || "$DB_NAME" == *$'\n'* ]]; then
  echo "Missing or invalid database credentials for schema owner '$schema'. Check provisioning and the selected environment." >&2
  exit 1
fi

pgpass_file=
port_forward_log=
port_forward_pid=

cleanup() {
  status=$?
  trap - EXIT
  if [[ -n "$port_forward_pid" ]]; then
    kill "$port_forward_pid" 2>/dev/null || true
    wait "$port_forward_pid" 2>/dev/null || true
  fi
  rm -f "$pgpass_file" "$port_forward_log"
  exit "$status"
}
trap cleanup EXIT

pgpass_file=$(mktemp)
port_forward_log=$(mktemp)
chmod 600 "$pgpass_file"
pgpass_database=${DB_NAME//\\/\\\\}
pgpass_database=${pgpass_database//:/\\:}
pgpass_password=${password//\\/\\\\}
pgpass_password=${pgpass_password//:/\\:}
printf '127.0.0.1:%s:%s:%s:%s\n' \
  "$LOCAL_PORT" "$pgpass_database" "$username" "$pgpass_password" > "$pgpass_file"

kubectl --context "$CONTEXT_NAME" -n "$DB_NAMESPACE" port-forward \
  --address 127.0.0.1 "service/$DB_SERVICE" "$LOCAL_PORT:5432" \
  > "$port_forward_log" 2>&1 &
port_forward_pid=$!

port_forward_ready=false
for (( attempt = 0; attempt < 50; attempt++ )); do
  if ! kill -0 "$port_forward_pid" 2>/dev/null; then
    echo "PostgreSQL port-forward failed:" >&2
    cat "$port_forward_log" >&2
    exit 1
  fi
  if [[ $(<"$port_forward_log") == *"Forwarding from 127.0.0.1:$LOCAL_PORT ->"* ]]; then
    port_forward_ready=true
    break
  fi
  sleep 0.1
done

if [[ "$port_forward_ready" != true ]]; then
  echo "Timed out waiting for PostgreSQL on localhost:$LOCAL_PORT" >&2
  cat "$port_forward_log" >&2
  exit 1
fi

echo "Connecting to production database '$DB_NAME' as '$username' (schema '$schema')." >&2
echo "Exit psql with \\q; the port-forward will then close automatically." >&2
unset PGPASSWORD PGHOSTADDR PGSERVICE PGSERVICEFILE
PGAPPNAME="$VAULT_NAME-terminal-$schema" \
PGOPTIONS="-c search_path=$schema,public" \
PGPASSFILE="$pgpass_file" \
  psql \
    --no-password \
    --host 127.0.0.1 \
    --port "$LOCAL_PORT" \
    --dbname "$DB_NAME" \
    --username "$username" \
    --set ON_ERROR_STOP=on
