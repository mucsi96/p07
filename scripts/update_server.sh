#!/bin/bash

set -euo pipefail

required_variables=(
  SERVER_SSH_HOST
  SERVER_SSH_PORT
  SERVER_SSH_USER
  SERVER_SSH_PRIVATE_KEY
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    printf 'Error: %s is required.\n' "$variable" >&2
    exit 1
  fi
done

if [[ ! "$SERVER_SSH_PORT" =~ ^[1-9][0-9]*$ ]] ||
  (( 10#$SERVER_SSH_PORT > 65535 )); then
  echo "Error: SERVER_SSH_PORT must be a valid TCP port." >&2
  exit 1
fi

for command in ssh mktemp; do
  command -v "$command" >/dev/null || {
    printf "Error: '%s' is required.\n" "$command" >&2
    exit 1
  }
done

ssh_key=$(mktemp)
known_hosts=$(mktemp)
trap 'rm -f -- "$ssh_key" "$known_hosts"' EXIT

printf '%s\n' "$SERVER_SSH_PRIVATE_KEY" >"$ssh_key"
chmod 600 "$ssh_key"

ssh_options=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o ConnectionAttempts=3
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=4
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$known_hosts"
  -i "$ssh_key"
  -p "$SERVER_SSH_PORT"
)
ssh_target="$SERVER_SSH_USER@$SERVER_SSH_HOST"

boot_id=$(ssh "${ssh_options[@]}" "$ssh_target" '
  set -eu
  . /etc/os-release
  if [ "$ID" != debian ] || [ "$VERSION_ID" != 13 ]; then
    echo "Expected Debian 13, found ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi
  sudo -n true
  cat /proc/sys/kernel/random/boot_id
')

echo "Updating all Debian packages, including kernel and security updates..."
update_status=0
ssh "${ssh_options[@]}" "$ssh_target" \
  'sudo -n flock --wait 900 /run/lock/github-actions-system-update.lock /bin/bash -se' <<'REMOTE_SCRIPT' || update_status=$?
export APT_LISTCHANGES_FRONTEND=none
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

update_status=0
apt-get update || update_status=$?
if (( update_status == 0 )); then
  apt-get \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -y dist-upgrade || update_status=$?
fi
if (( update_status == 0 )); then
  apt-get -y autoremove --purge || update_status=$?
fi

reboot_unit="github-actions-reboot-$(date +%s)"
systemd-run \
  --unit="$reboot_unit" \
  --on-active=10s \
  --collect \
  /usr/bin/systemctl reboot
exit "$update_status"
REMOTE_SCRIPT

echo "Updates completed and reboot scheduled; waiting for the server to return..."
deadline=$((SECONDS + 900))
sleep 15

while (( SECONDS < deadline )); do
  if current_boot_id=$(ssh "${ssh_options[@]}" "$ssh_target" \
    'cat /proc/sys/kernel/random/boot_id' 2>/dev/null) &&
    [[ -n "$current_boot_id" && "$current_boot_id" != "$boot_id" ]]; then
    echo "Server restarted successfully."
    if (( update_status != 0 )); then
      printf 'Error: package update failed with status %d before the restart.\n' \
        "$update_status" >&2
      exit "$update_status"
    fi
    exit 0
  fi

  sleep 10
done

echo "Error: server did not return with a new boot ID within 15 minutes." >&2
exit 1
