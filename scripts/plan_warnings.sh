#!/bin/bash

set -euo pipefail

source .venv/bin/activate

terraform plan -json 2>&1 \
  | jq -r 'select(.type == "diagnostic" and .diagnostic.severity == "warning") | .diagnostic | "\(.summary)\n  \(.detail)\n  at: \(.range.filename // "unknown"):\(.range.start.line // "?")\n"'
