# p07

Netcup based Kubernetes environment instance.

This repository wires together reusable Terraform modules from
[mucsi96/k8s-modules](https://github.com/mucsi96/k8s-modules) to provision a
single-node k3s cluster on an existing Netcup RS 1000 G12 running Debian 13,
plus the supporting platform components (k3s-packaged Traefik with Gateway API,
Cloudflare edge security, and Entra authentication).

Terraform state, secrets, and the OIDC discovery document live in Azure
(remote backend storage account, Key Vault, static website).

## Modules used

| Module | Purpose |
|---|---|
| `provision_server` | Reinstalls and configures an existing Netcup RS 1000 G12 through the SCP API |
| `setup_cluster` | Hardens Debian, installs k3s, and enables Azure Workload Identity OIDC |
| `setup_ingress_controller` | Configures k3s-packaged Traefik, Gateway API, Cloudflare DNS/security, and origin TLS |
| `setup_monitoring_crds` | Installs the monitoring CRDs required by PostgreSQL and VictoriaMetrics |
| `setup_victoria_metrics` | Installs VictoriaMetrics, Grafana, and exporters |
| `setup_victoria_logs` | Installs Alloy log/Faro collection and exposes the Faro receiver |

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
provides `az`, `terraform`, `helm`, `kubectl`, `node`, `psql`, `redis-cli`,
`kubelogin`, `jq`, `curl`, `ssh-agent`, and `python3`. Install the
[`azwi`](https://github.com/Azure/azure-workload-identity/releases) executable
separately; it is used to publish the cluster's OIDC discovery documents.

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

Once installed, entering the dev shell (`nix develop`) checks the client's
status and, when it isn't `online`, reminds you how to connect:

```bash
twingate start   # starts the daemon (prompts for sudo) and connects
```

On this headless WSL box Twingate cannot open a browser to complete login.
When it needs authentication, run the notifier in a second terminal to surface
the auth URL, then open that URL in your Windows browser and log in:

```bash
twingate-notifier console
```

The same applies to the per-resource authentication in `scripts/create.sh` and
`scripts/destroy.sh` (`twingate auth <resource>`): keep a `twingate-notifier
console` open in another terminal during those runs to catch each resource's
auth URL.

### Netcup server

Order an RS 1000 G12 before applying. The SCP API manages existing contracts
but cannot order a server. Obtain these values from the SCP API:

- Numeric `netcup_server_id` from `GET /api/v1/servers` (not the `v...`
  server name shown in SCP).
- Internal `netcup_user_id` from the authenticated SCP profile (not the CCP
  customer number used to sign in).

Start Netcup's device authorization flow and save the internal user ID, refresh
token, Debian 13 UEFI image flavour ID, and disk name directly to Azure Key
Vault with:

```bash
bash scripts/authenticate_netcup.sh
```

Open the URL printed by the script, sign in to SCP, and approve access. Set
`AZURE_KEYVAULT_NAME` to override the default `p07` vault. If the account has
multiple servers and `netcup-server-id` is not already present, set the numeric
`NETCUP_SERVER_ID` for the discovery run.

Store them in Azure Key Vault using the secret names below. The authentication
script selects the server's Debian 13 UEFI image flavour and its single disk from
the SCP API. The hardcoded `reinstall_generation = "initial"` is not a Netcup
setting; it records approval for the first destructive installation. Changing
that string later deliberately triggers another disk erase and reinstall.
The server module exchanges the stored refresh token for short-lived access
tokens as needed and persists Netcup's rotated token after each apply.

### Azure backend

Bootstrap the resource group, Key Vault, storage account, and tfstate
container, and write `backend.tf` locally:

```bash
bash scripts/init.sh p07
```

### Azure Key Vault secrets

The `p07` Key Vault is the persistent master vault. Populate the following
platform secrets before running `scripts/create.sh`:

| Secret Name | Description | Where to retrieve the value |
|---|---|---|
| `dns-zone` | DNS zone domain used by all applications | [Cloudflare dashboard → your zone → Overview](https://dash.cloudflare.com/) |
| `letsencrypt-email` | Email address for Let's Encrypt certificate registration | Your own contact mailbox |
| `cloudflare-zone-id` | Cloudflare zone ID for DNS management | [Cloudflare dashboard → your zone → Overview → API section (right sidebar)](https://dash.cloudflare.com/) |
| `authorized-as` | Numeric network ASN allowed by the Cloudflare firewall rules | Your trusted network provider's ASN |
| `github-token` | GitHub personal access token with `repo` scope | [GitHub → Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens) |
| `cloudflare-api-token` | Cloudflare API token for DNS, rulesets, certificates, and email routing | [Cloudflare dashboard → API Tokens](https://dash.cloudflare.com/profile/api-tokens) |
| `twingate-network` | Twingate network name | Twingate Admin Console |
| `twingate-api-token` | Twingate API token | Twingate Admin Console |
| `netcup-server-id` | Existing RS 1000 G12 server ID | `GET /api/v1/servers` |
| `netcup-user-id` | Internal SCP user ID | `scripts/authenticate_netcup.sh` |
| `netcup-refresh-token` | Long-lived SCP OpenID Connect refresh token | `scripts/authenticate_netcup.sh` |
| `netcup-image-flavour-id` | Server-specific Debian 13 image flavour ID | `scripts/authenticate_netcup.sh` |
| `netcup-disk-name` | Server disk selected for the destructive installation | `scripts/authenticate_netcup.sh` |

Application-owned credentials also live in the master vault. Their names use
an app prefix; Terraform copies each value to the app-specific vault without
that prefix. Populate all of these before running `scripts/create.sh`:

| Master Secret Name | App Vault | App Secret Name |
|---|---|---|
| `hello-claude-api-key` | `p07-hello` | `claude-api-key` |
| `learn-language-claude-api-key` | `p07-learn-language` | `claude-api-key` |
| `learn-language-eleven-labs-api-key` | `p07-learn-language` | `eleven-labs-api-key` |
| `learn-language-google-ai-api-key` | `p07-learn-language` | `google-ai-api-key` |
| `learn-language-ideogram-api-key` | `p07-learn-language` | `ideogram-api-key` |
| `learn-language-openai-api-key` | `p07-learn-language` | `openai-api-key` |
| `learn-language-xai-api-key` | `p07-learn-language` | `xai-api-key` |
| `training-log-strava-client-id` | `p07-training-log` | `strava-client-id` |
| `training-log-strava-client-secret` | `p07-training-log` | `strava-client-secret` |
| `training-log-withings-client-id` | `p07-training-log` | `withings-client-id` |
| `training-log-withings-client-secret` | `p07-training-log` | `withings-client-secret` |
| `library-openai-api-key` | `p07-library` | `openai-api-key` |
| `cooking-claude-api-key` | `p07-cooking` | `claude-api-key` |
| `cooking-openai-api-key` | `p07-cooking` | `openai-api-key` |

Terraform will write back the following Key Vault secrets after a successful
apply: `host`, `ssh-user-name`, `ssh-port`, `ssh-private-key`, the rotated
`netcup-refresh-token`, `issuer`, `tenant-id` plus the cluster credentials
written by the `setup_cluster` module (`k8s-config`, `k8s-host`,
`k8s-client-certificate`, `k8s-client-key`, `k8s-cluster-ca-certificate`).

## Usage

All commands assume you are inside the Nix dev shell (`nix develop` or direnv).

```bash
# Refresh the Python venv, Ansible collections, Helm repo, and Terraform init
bash scripts/install_dependencies.sh

# Plan + apply the environment
bash scripts/create.sh

# Merge the admin config into ~/.kube/config, activate p07, and verify access
bash scripts/pull_kube_admin_config.sh

# Destroy Terraform-managed resources. This does not cancel the Netcup
# contract or erase the server disk.
bash scripts/destroy.sh
```

### Database roles

Each database-backed application module provisions its own non-administrator
login role and same-named schema. The PostgreSQL module only owns the database
server, while the backup service consumes each application module's schema-owner
credentials for schema-scoped backup and restore operations.

Module release `v-71` provisions roles and schemas during Terraform apply over
the existing operator SSH connection. The database descriptor includes its
deployment, storage instance ID, and SSH host/port/user. `scripts/create.sh`
loads the SSH agent; provisioning needs operator Twingate access and trusts new
SSH hosts on first use, rejecting changed host keys.

Convenience helpers:

- `scripts/authenticate_netcup.sh` — authorize through Netcup's OAuth device
  flow and store the refresh token in Azure Key Vault.
- `scripts/postgres_shell.sh` — choose an application and open `psql` against
  its production schema using the application's owner role. Pass a schema or
  app slug (for example, `scripts/postgres_shell.sh training-log`) to skip the
  menu. Credentials come from the selected application's Azure Key Vault;
  Grafana alone uses the retained `monitoring/grafana-database` runtime Secret.
  Requires Azure login and vault-read permissions, a configured Kubernetes
  context, and Twingate access. `AZURE_KEYVAULT_NAME` selects the environment
  prefix (default `p07`); `KUBE_CONTEXT_NAME` defaults to that same name.
  `POSTGRES_NAMESPACE`, `POSTGRES_SERVICE`, `POSTGRES_DATABASE`, and
  `POSTGRES_LOCAL_PORT` retain their overrides. The loopback-only port-forward
  and private temporary password file are removed when the shell exits.
- `scripts/ssh_to_server.sh` — SSH into the Netcup server using the
  stored key/port/user from Key Vault.
- `scripts/expose_traefik_dashboard.sh` — port-forward the Traefik
  dashboard to `http://localhost:8080/dashboard/`.

## Configuration

Netcup identifiers, authentication, and image selection are loaded from Azure
Key Vault; the remaining server settings are hardcoded. The root variables (`environment_name`,
`azure_subscription_id`, `azure_location`, `storage_account_name`) are written
to `backend.tf` by `scripts/init.yaml` during bootstrap.
