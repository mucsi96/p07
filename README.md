# p07

Hetzner Cloud based Kubernetes environment instance.

This repository wires together reusable Terraform modules from
[mucsi96/k8s-modules](https://github.com/mucsi96/k8s-modules) to provision a
single-node MicroK8s cluster on a Hetzner Cloud
[CX42](https://www.hetzner.com/cloud) server (8 vCPU, 16 GB RAM, 160 GB SSD,
~€16.40/month) plus the supporting platform components (Traefik ingress with
Cloudflare tunnel + SSO).

Terraform state, secrets, and the OIDC discovery document live in Azure
(remote backend storage account, Key Vault, static website).

## Modules used

| Module | Purpose |
|---|---|
| `provision_hetzner_server` | Creates the Hetzner Cloud CX42 server with cloud-init bootstrap |
| `setup_cluster` | Hardens the server, installs MicroK8s, enables Azure Workload Identity OIDC |
| `setup_ingress_controller` | Installs Traefik, configures Cloudflare Tunnel, ZTNA SSO via Entra ID |

## Prerequisites

### Tools

Run `scripts/install_dependencies.sh` on Ubuntu (it installs `az`, `terraform`,
`helm`, `node`, `azwi`, the Ansible collections, and seeds the local Python
virtual environment from `requirements.txt`/`requirements.yml`).

A Python virtual environment is expected at `.venv/` — create it once with:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

### Azure backend

Bootstrap the resource group, Key Vault, storage account, and tfstate
container, and write `backend.tf` locally:

```bash
bash scripts/init.sh p07
```

### Azure Key Vault secrets

Populate the following secrets in the `p07` Key Vault before running
`terraform apply`:

| Secret Name | Description | Where to retrieve the value |
|---|---|---|
| `hcloud-token` | Hetzner Cloud API token with read & write permissions | [Hetzner Cloud Console → your project → Security → API tokens](https://console.hetzner.cloud/projects) |
| `dns-zone` | DNS zone domain used by all applications | [Cloudflare dashboard → your zone → Overview](https://dash.cloudflare.com/) |
| `letsencrypt-email` | Email address for Let's Encrypt certificate registration | Your own contact mailbox |
| `cloudflare-zone-id` | Cloudflare zone ID for DNS management | [Cloudflare dashboard → your zone → Overview → API section (right sidebar)](https://dash.cloudflare.com/) |
| `authorized-as` | Authorized identity/email for SSO access policies | [Microsoft Entra admin center → Users](https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserManagementMenuBlade/~/AllUsers) |
| `github-token` | GitHub personal access token with `repo` scope | [GitHub → Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens) |

Terraform will write back the following Key Vault secrets after a successful
apply: `host`, `ssh-user-name`, `ssh-port`, `ssh-private-key`, `user-password`,
`issuer`, `tenant-id` plus the cluster credentials
written by the `setup_cluster` module (`k8s-config`, `k8s-host`,
`k8s-client-certificate`, `k8s-client-key`, `k8s-cluster-ca-certificate`).

## Usage

```bash
# Install/refresh tools, providers, and Ansible collections
bash scripts/install_dependencies.sh

# Plan + apply the environment
bash scripts/create.sh

# Pull the admin kubeconfig into ./.kube/admin-config
bash scripts/pull_kube_admin_config.sh

# Tear it all down
bash scripts/destroy.sh
```

Convenience helpers:

- `scripts/ssh_to_server.sh` — SSH into the Hetzner server using the
  stored key/port/user from Key Vault.
- `scripts/expose_traefik_dashboard.sh` — port-forward the Traefik
  dashboard to `http://localhost:8080/dashboard/`.

## Customisation

`variables.tf` exposes the Hetzner datacenter location (defaults to `fsn1`).
The other root variables (`environment_name`, `azure_subscription_id`,
`azure_location`, `storage_account_name`) are written to `backend.tf` by
`scripts/init.yaml` during bootstrap.
