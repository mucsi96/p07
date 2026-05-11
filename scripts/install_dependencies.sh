#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

VAULT_NAME=${AZURE_KEYVAULT_NAME:-p07}

# Detect if running on Ubuntu
if [ "$(uname -s)" = "Linux" ] && [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "ubuntu" ]; then
        echo "Running on Ubuntu. Checking dependencies..."

        # Check and install azure-cli
        if ! command -v az &> /dev/null; then
            echo "Installing Azure CLI..."
            curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        else
            echo "Azure CLI is already installed."
        fi

        # Check and install terraform
        if ! command -v terraform &> /dev/null; then
            echo "Installing Terraform..."
            sudo snap install terraform --classic
        else
            echo "Terraform is already installed."
        fi

        # Check and install helm
        if ! command -v helm &> /dev/null; then
            echo "Installing Helm..."
            sudo snap install helm --classic
        else
            echo "Helm is already installed."
        fi

        # Check and install NodeJS
        if ! command -v node &> /dev/null; then
            echo "Installing NodeJS..."
            sudo snap install node --classic
        else
            echo "NodeJS is already installed."
        fi

        # Check and install redis-cli
        if ! command -v redis-cli &> /dev/null; then
            echo "Installing redis-tools..."
            sudo apt-get update && sudo apt-get install -y redis-tools
        else
            echo "redis-cli is already installed."
        fi

        # Check and install azwi
        if ! command -v azwi &> /dev/null; then
            echo "Installing azwi..."
            tmp_dir=$(mktemp -d)
            azwi_version=$(curl -s https://api.github.com/repos/Azure/azure-workload-identity/releases/latest | grep -m1 '"tag_name":' | cut -d'"' -f4 || true)
            curl -sL "https://github.com/Azure/azure-workload-identity/releases/download/${azwi_version}/azwi-${azwi_version}-linux-amd64.tar.gz" -o "$tmp_dir/azwi.tar.gz"
            sudo tar -xzf "$tmp_dir/azwi.tar.gz" -C /usr/local/bin azwi
            sudo chmod 755 /usr/local/bin/azwi
            rm -rf "$tmp_dir"
        else
            echo "azwi is already installed."
        fi

        # Check and install kubelogin (used by .kube/oidc-config exec block to
        # mint Entra ID tokens for kube-apiserver; works for both `az login`
        # users and GitHub workload-identity pipelines).
        if ! command -v kubelogin &> /dev/null; then
            echo "Installing kubelogin..."
            tmp_dir=$(mktemp -d)
            kubelogin_version=$(curl -s https://api.github.com/repos/Azure/kubelogin/releases/latest | grep -m1 '"tag_name":' | cut -d'"' -f4 || true)
            curl -sL "https://github.com/Azure/kubelogin/releases/download/${kubelogin_version}/kubelogin-linux-amd64.zip" -o "$tmp_dir/kubelogin.zip"
            unzip -q "$tmp_dir/kubelogin.zip" -d "$tmp_dir"
            sudo install -m 0755 "$tmp_dir/bin/linux_amd64/kubelogin" /usr/local/bin/kubelogin
            rm -rf "$tmp_dir"
        else
            echo "kubelogin is already installed."
        fi

    fi
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
