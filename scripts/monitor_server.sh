#!/bin/bash
# Streams memory, CPU, and disk usage from the remote server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INTERVAL=${MONITOR_INTERVAL:-2}
ONCE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--once] [--interval=SECONDS]

Streams memory, CPU and disk usage from the server reached by ssh_to_server.sh.

Options:
  --once               Print a single snapshot and exit.
  --interval=SECONDS   Refresh interval when streaming (default: ${INTERVAL}).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --once|-1) ONCE=true ;;
    --interval=*) INTERVAL="${arg#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

remote_snapshot='
printf "===== %s =====\n\n" "$(date)"
printf -- "--- Memory ---\n"
free -h
printf "\n--- CPU ---\n"
uptime
top -bn1 | awk "/^%Cpu/ {print; exit}"
printf "\n--- Disk ---\n"
df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay
'

if [ "$ONCE" = true ]; then
  remote_cmd="$remote_snapshot"
else
  remote_cmd="while true; do printf '\\033[H\\033[2J'; $remote_snapshot; sleep $INTERVAL; done"
fi

exec "$SCRIPT_DIR/ssh_to_server.sh" "$remote_cmd"
