#!/bin/bash

set -euo pipefail

source .venv/bin/activate

terraform destroy
