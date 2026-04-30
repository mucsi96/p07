#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

resourceGroupName=p07

source .venv/bin/activate

ansible-playbook --inventory localhost, --extra-vars "resource_group_name=$resourceGroupName" scripts/init.yaml

echo "Azure resources for Terraform backend are configured."

terraform init
