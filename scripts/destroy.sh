#!/bin/bash

set -euo pipefail

source .venv/bin/activate

terraform destroy -refresh=false -auto-approve -target=module.provision_hetzner_server

# terraform destroy -refresh=false -auto-approve
