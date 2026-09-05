#!/bin/bash
set -euo pipefail

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}
SECRET_NAME=netcup-refresh-token
IMAGE_SECRET_NAME=netcup-image-flavour-id
DISK_SECRET_NAME=netcup-disk-name
USER_SECRET_NAME=netcup-user-id
CLIENT_ID=scp
NETCUP_API_URL=https://www.servercontrolpanel.de/scp-core
DEVICE_AUTH_URL=https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/auth/device
TOKEN_URL=https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/token
USERINFO_URL=https://www.servercontrolpanel.de/realms/scp/protocol/openid-connect/userinfo

for command in az curl jq; do
  command -v "$command" >/dev/null || {
    echo "Error: '$command' is required." >&2
    exit 1
  }
done

az account show --output none

device_response=$(curl --fail-with-body --silent --show-error \
  --request POST "$DEVICE_AUTH_URL" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode 'scope=offline_access openid')

device_code=$(jq -er '.device_code | select(type == "string" and length > 0)' <<<"$device_response")
verification_url=$(jq -er '(.verification_uri_complete // .verification_uri) | select(type == "string" and length > 0)' <<<"$device_response")
user_code=$(jq -r '.user_code // ""' <<<"$device_response")
expires_in=$(jq -er '.expires_in | numbers | floor' <<<"$device_response")
interval=$(jq -er '(.interval // 5) | numbers | floor' <<<"$device_response")
deadline=$(($(date +%s) + expires_in))

printf 'Open this URL and approve access to Netcup SCP:\n%s\n' "$verification_url"
if [[ -n "$user_code" && "$verification_url" != *"$user_code"* ]]; then
  printf 'Enter code: %s\n' "$user_code"
fi

while (( $(date +%s) < deadline )); do
  sleep "$interval"
  token_response=$(curl --silent --show-error \
    --request POST "$TOKEN_URL" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "device_code=$device_code")
  error=$(jq -er '.error // ""' <<<"$token_response")

  case "$error" in
    "")
      refresh_token=$(jq -er '.refresh_token | select(type == "string" and length > 0)' <<<"$token_response")
      access_token=$(jq -er '.access_token | select(type == "string" and length > 0)' <<<"$token_response")
      az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "$SECRET_NAME" \
        --value "$refresh_token" \
        --output none

      user_id=$(curl --fail-with-body --silent --show-error \
        --header "Authorization: Bearer $access_token" \
        "$USERINFO_URL" | jq -er '.id | tonumber')
      az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "$USER_SECRET_NAME" \
        --value "$user_id" \
        --output none

      server_id=${NETCUP_SERVER_ID:-}
      if [[ -z "$server_id" ]]; then
        server_id=$(az keyvault secret show \
          --vault-name "$VAULT_NAME" \
          --name netcup-server-id \
          --query value \
          --output tsv 2>/dev/null || true)
      fi
      if [[ ! "$server_id" =~ ^[0-9]+$ ]]; then
        servers=$(curl --fail-with-body --silent --show-error \
          --header 'Accept: application/json' \
          --header "Authorization: Bearer $access_token" \
          "$NETCUP_API_URL/api/v1/servers")
        server_id=$(jq -er --arg server_name "$server_id" '
          if $server_name == "" then [.[] | .id]
          else [.[] | select(.name == $server_name) | .id]
          end
          | if length == 1 then .[0]
            else error("expected exactly one server; set NETCUP_SERVER_ID or seed netcup-server-id")
            end
        ' <<<"$servers")
      fi
      az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name netcup-server-id \
        --value "$server_id" \
        --output none
      image_flavours=$(curl --fail-with-body --silent --show-error \
        --header 'Accept: application/json' \
        --header "Authorization: Bearer $access_token" \
        "$NETCUP_API_URL/api/v1/servers/$server_id/imageflavours")
      image_flavour_id=$(jq -er '
        [
          .[]
          | select(
              [(.name // ""), (.alias // ""), (.text // ""), (.image.name // "")]
              | join(" ")
              | ascii_downcase
              | test("debian 13.*uefi")
            )
          | .id
        ]
        | if length == 1 then .[0] else error("expected exactly one Debian 13 UEFI image flavour") end
      ' <<<"$image_flavours")
      disks=$(curl --fail-with-body --silent --show-error \
        --header 'Accept: application/json' \
        --header "Authorization: Bearer $access_token" \
        "$NETCUP_API_URL/api/v1/servers/$server_id/disks")
      disk_name=$(jq -er '
        [.[] | (.name // .dev // empty)]
        | if length == 1 then .[0] else error("expected exactly one server disk") end
      ' <<<"$disks")
      az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "$IMAGE_SECRET_NAME" \
        --value "$image_flavour_id" \
        --output none
      az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "$DISK_SECRET_NAME" \
        --value "$disk_name" \
        --output none

      echo "Saved Netcup authentication and server metadata in Azure Key Vault $VAULT_NAME."
      exit 0
      ;;
    authorization_pending)
      ;;
    slow_down)
      interval=$((interval + 5))
      ;;
    access_denied | expired_token)
      echo "Netcup authorization failed: $error" >&2
      exit 1
      ;;
    *)
      description=$(jq -r '.error_description // .error' <<<"$token_response")
      echo "Netcup authorization failed: $description" >&2
      exit 1
      ;;
  esac
done

echo "Netcup device authorization expired before it was approved." >&2
exit 1
