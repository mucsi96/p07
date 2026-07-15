#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}

# All CLI tools (az, terraform, helm, kubectl, node, redis-cli, azwi,
# kubelogin, jq, python3) are provided by the Nix flake dev shell — enter it
# with `nix develop` (or via direnv and the committed .envrc) before running
# this script.
for tool in az terraform helm python3; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: '$tool' not found in PATH." >&2
        echo "Enter the Nix dev shell first: nix develop" >&2
        exit 1
    fi
done

# Twingate is the one dependency that cannot come from the flake: its client
# relies on a system-level systemd service (runs inside WSL so Terraform and
# the tunnel share the same network namespace; requires [boot] systemd=true
# in /etc/wsl.conf), so it has to be installed system-wide.
if ! command -v twingate &> /dev/null; then
    echo "Note: Twingate client not found. Install it system-wide with:"
    echo "  curl -s https://binaries.twingate.com/client/linux/install.sh | sudo bash"
fi

# Seed the local Python virtual environment. Terraform's ansible provider
# uses .venv/bin/python3 as its interpreter (see main.tf), so the venv path
# must stay stable even though python itself comes from the flake.
if [ ! -d .venv ]; then
    echo "Creating Python virtual environment at .venv..."
    python3 -m venv .venv
fi

source .venv/bin/activate

python3 -m pip install -r requirements.txt

ansible-galaxy collection install -r requirements.yml

python3 -m pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt

# Add the Helm repository
helm repo add mucsi96 https://mucsi96.github.io/k8s-helm-charts

# Check if backend.tf exists
if [ ! -f backend.tf ]; then
    echo "Fetching backend configuration from Key Vault..."
    az keyvault secret show \
      --vault-name "$VAULT_NAME" \
      --name remote-backend-config \
      --query value \
      --output tsv > backend.tf
    echo "Backend configuration saved to backend.tf."

    echo "Initializing Terraform..."
    terraform init --upgrade
else
    echo "Backend configuration already exists."
    terraform init
fi
