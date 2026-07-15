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

All CLI tools come from the Nix flake dev shell. Install
[Nix](https://nixos.org/download/) with flakes enabled (add
`experimental-features = nix-command flakes` to `~/.config/nix/nix.conf` if
needed), then enter the shell from the repository root:

```bash
nix develop
```

Alternatively install [direnv](https://direnv.net/) and run `direnv allow`
once — the committed `.envrc` then loads the shell automatically. The shell
provides `az`, `terraform`, `helm`, `kubectl`, `node`, `redis-cli`, `azwi`,
`kubelogin`, `jq`, and `python3`.

Inside the shell, run `scripts/install_dependencies.sh` — it seeds the local
Python virtual environment at `.venv/` from
`requirements.txt`/`requirements.yml` (Terraform's ansible provider uses
`.venv/bin/python3` as its interpreter), installs the Ansible collections,
adds the Helm repository, and initializes the Terraform backend.

The one exception is the Twingate client: it needs a system-level systemd
service, so it cannot come from the flake. Install it once system-wide:

```bash
curl -s https://binaries.twingate.com/client/linux/install.sh | sudo bash
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

All commands assume you are inside the Nix dev shell (`nix develop` or direnv).

```bash
# Refresh the Python venv, Ansible collections, Helm repo, and Terraform init
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
