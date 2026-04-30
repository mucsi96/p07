#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

resourceGroupName="$1"

if [ -z "$resourceGroupName" ]; then
  echo "Usage: $0 <resource-group-name>"
  exit 1
fi

ansible-playbook --inventory localhost, --extra-vars "resource_group_name=$resourceGroupName" scripts/init.yaml

echo "Azure resources for Terraform backend are configured."

terraform init
