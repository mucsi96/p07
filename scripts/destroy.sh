#!/bin/bash

set -euo pipefail

source .venv/bin/activate

terraform destroy -refresh=false -auto-approve -target=module.register_cluster_apiserver_oidc_app

# terraform destroy -refresh=false -auto-approve
