#!/bin/bash

set -euo pipefail

source .venv/bin/activate

terraform destroy -target=module.setup_ingress_controller

# terraform destroy
