# p07

Netcup based Kubernetes environment instance.

## Code review and maintenance automation

The fleet uses subscription-backed native Codex GitHub reviews and ChatGPT/Codex
scheduled maintenance tasks. See [the migration inventory](docs/codex-migration.md)
for repository coverage, activation status, and the skeleton-sync and Terraform-update
schedules. Account-side activation is required in addition to these repository files.

This repository wires together reusable Terraform modules from
[mucsi96/k8s-modules](https://github.com/mucsi96/k8s-modules) to provision a
single-node k3s cluster on an existing Netcup RS 1000 G12 running Debian 13,
plus the supporting platform components (k3s-packaged Traefik with Gateway API,
Cloudflare edge security, and Entra authentication).

Terraform state, secrets, and the OIDC discovery document live in Azure
(remote backend storage account, Key Vault, static website).

## Application infrastructure ownership

Application-specific Terraform lives directly in this repository:
`hello.tf`, `cooking.tf`, `library.tf`, `learn_language.tf`, `training_log.tf`,
`expense_tracker.tf`, `observatory.tf`, `backup.tf`, and `bank_email_worker.tf`.
The bank email worker source is `workers/bank-email.js`. Party's definition is
retained in `party.tf.disabled`, matching its previously disabled configuration.

These files compose published, explicitly pinned `k8s-modules` building blocks
for app namespaces/deployment identities, Entra registrations, PostgreSQL schemas,
static storage and ForwardAuth. App-specific roles, secrets, inventory, volumes
and integrations belong here; workloads and image/chart deployment remain owned
by each application's repository.

The live p07 state has already migrated to these top-level definitions, and the
completed move blocks have been removed. See [the ownership migration](docs/application-ownership.md)
for the applied result and compatibility with older state snapshots.

## Learn Language story storage

`learn_language.tf` grants the Learn Language API workload identity **Storage
Blob Data Reader** on the existing `learn-language` container in storage account
`ibari` (resource group `ibari`), including the `stories/` prefix. Story discovery lists blobs and reads transcripts
and audio using this identity. Apply this permission before deploying Azure audio
collections; without it, discovery fails with `AuthorizationPermissionMismatch`.
The storage account and container are referenced as data sources, not managed here.

Existing app audio, images, and PDFs use the local `/app/storage` persistent volume
since the November 2025 storage migration, not Azure RBAC. The identically named
`audio/`, `images/`, and `sources/` folders still present in Azure do not imply an
existing API role assignment. The container-scoped reader role also covers new
story folders, so moving collections under `stories/` needs no additional grant.

Applied on 2026-11-07 with `scripts/create.sh`: 1 added, 1 changed (Netcup refresh
token rotation), and 0 destroyed. Blob listing and transcript download were
verified with the running API pod's workload identity, both returning HTTP 200.

## Static client hosting

Learn Language's migration is defined in `learn_language.tf` for
https://github.com/mucsi96/learn-language/pull/487, following the
[shared architecture](https://github.com/mucsi96/skeleton-app/issues/105).
Apply infrastructure before the application deployment: Entra Web registration,
Redis-backed per-app ForwardAuth, Azure static website and public assets with
app-origin CORS, scoped upload permissions, `client-storage-config` and
`forward-auth-config` deployment secrets, and same-origin Faro routing.
The existing SPA registration remains until the application rollout is verified.
Exact `POST /api/dictionary` and `GET /api/known-cards` routes target
`learn-language-server:8080`, retaining caller bearer headers for backend-scoped
token validation. `/api/environment` uses the ordinary authenticated API route.
The app pipeline uploads assets before index and deploys the authenticated API
and static-client charts. Verify login/deep links, both token APIs, and Faro after
deployment; retire the legacy SPA registration in a later change.
Infrastructure was applied on 2026-11-02: 20 resources added across the initial
interrupted run and successful retry, 2 updated, and none destroyed. The auth
deployment is ready and both OAuth and token-exclusion routes are accepted with
resolved backend references. Application deployment remains the next rollout step.

Training Log's gateway/static-hosting migration is provisioned in `training_log.tf`
for https://github.com/mucsi96/training-log-pro/issues/194. Apply this infrastructure
before the application migration: it adds the Web registration, per-app
ForwardAuth, static storage/upload permissions and deployment secrets, and adds
the same-origin Faro host. The existing SPA registration remains during rollout
so the current UI continues working until the app deploy; retire it separately
after verification. Database/schema, PVs, API identity/roles and encrypted provider
tokens keep their existing resources. The application owns the more-specific
device API-key and OAuth callback routes and deploys them before enabling API
ForwardAuth. No infrastructure apply is part of this proposed change.

Backup's gateway authentication and static hosting are defined in `backup.tf`,
using the same hosting and build-time Faro pattern, pending infrastructure rollout.

Skeleton/Hello, Observatory and Cooking use the same Azure Storage contract: `$web` holds index HTML and a public-read
`assets` Blob container serves all browser assets directly with app-origin CORS.
Its pipeline has separately scoped Entra upload permissions for both containers.
The document-only `static-client-app` **5.0.0** chart provides authenticated SPA
routing. Faro configuration is compiled into each app; documents need no body
injection. Terraform publishes storage metadata and owns per-app ForwardAuth
**10.0.0**, including Grafana in email-header mode. All module sources pin
**v-104**, including the disabled Party definition.
`scripts/create.sh` completed on 2026-11-01 with no move blocks: 0 additions,
1 update (the rotated Netcup refresh token), and 0 deletions. Publishing
assets and deploying application charts remain owned by the app pipelines.

The v-103 upgrade was applied with operator approval on 2026-11-06 using
`scripts/create.sh`: 5 added, 10 changed, and 2 destroyed. Grafana now uses the
shared ForwardAuth module and chart 9.0.0 with its email allowlist. The old proxy
Helm resource and cookie generator were replaced; database and storage resources
had no planned changes. All nine proxy deployments became ready on chart 9.0.0.
Grafana's application and OAuth routes are accepted with resolved references.
Anonymous requests and spoofed identity headers both redirect to Entra through
Traefik. The public probe returned 403, and browser sign-in subsequently exposed
the email-claim bug corrected by the v-104 rollout below. Existing Grafana
users need a fresh login because the session cookie changed.

The v-104 follow-up was applied with operator approval on 2026-11-06 using
`scripts/create.sh`: 0 added, 10 changed, and 0 destroyed. All nine proxy releases
now run chart 10.0.0 and their deployments are ready. Grafana's live configuration
uses the email claim without the deprecated `userIDClaim` override that caused
post-login 403 responses; its email allowlist remains enforced. Both Grafana
HTTPRoutes are accepted with resolved references. The operator confirmed
successful Grafana browser sign-in after this rollout.

## Application dashboard

**Observatory** lives in its own repository,
[mucsi96/observatory-app](https://github.com/mucsi96/observatory-app): a Rust/Axum and
React dashboard for application health, deployed versions, deployment
jobs, open MRs/PRs with check statuses, issue counts, and direct issue creation.
`observatory.tf` provisions its inventory, read-only Kubernetes collector access, GitHub
deploy identity, Entra Web/API registrations and ingress NetworkPolicy.
Like skeleton-app, the UI uses per-app oauth2-proxy sessions and chart-owned
ForwardAuth Middleware. The API independently validates the forwarded token and
requires `api-access` and the `readApps` role. Creating issues through the dashboard
also requires `createIssues`. The `register_api` module declares both roles and
assigns both to the owner automatically. Additional issue authors need both roles
assigned on the **Observatory API** enterprise application in Entra; read-only
users need only `readApps`. After applying this role change, sign out of Observatory
and sign in again to obtain a fresh API token containing the new role.
It uses the same `register_api`/`register_web` modules and
`observatory-api-workload-identity` naming convention as the other apps.
Fleet snapshots are cached in memory and rebuilt after restarts.

The inventory also tracks `mucsi96/p07` and `mucsi96/k8s-modules` as
repository-only entries: PRs, checks, issues and dependency updates without Kubernetes
workloads. Empty namespaces skip Kubernetes collection and namespace RBAC;
workload health is shown as not applicable.

The app's `Pipeline` publishes a server image and tested static client archive and deploys
`mucsi96/rust-app` **7.0.0** and `mucsi96/static-client-app` **5.0.0**.
Their HTTPRoutes serve `/api` and `/` at `https://apps.<dns-zone>`.
p07 does not own image pins or build workflows. The GitHub deploy identity reads
scoped deployment secrets from the dedicated application vault and receives
namespace-scoped permissions for Helm/chart resources and Middleware in
`observatory`. The deploy script converts Terraform-owned source configuration
into chart-owned config/env Secrets, triggering checksum rollouts. The GitHub
credential is mounted separately from the Terraform-managed runtime Secret.

Logging exposes same-origin `/_telemetry/collect` on all three app hosts.
The Terraform GitHub token (`github-token` in Key Vault) needs repository
**Variables: Read and write** access in addition to its existing permissions,
so Terraform can manage `DEPLOY_ENABLED` in `observatory-app`.
Rerun the app pipeline after inventory changes. After token rotation, restart the
server Deployment to reload the mounted credential, which is read at startup.

#### Dedicated Observatory GitHub token

Create a dedicated fine-grained personal access token manually in GitHub (for
example, named `observatory`) and store it in the master `p07` Key Vault as
`observatory-github-token`. This is separate from `github-token`, which remains
the Terraform GitHub provider credential. Terraform reads the dedicated secret;
it does not create the PAT or manage its GitHub permissions. The new secret must
exist before applying this configuration; there is no fallback to `github-token`.
Terraform copies it to `observatory/observatory-github` (key `token`). The app's
deployment pipeline mounts that Secret read-only at `/credentials` and configures
`GITHUB_TOKEN_FILE=/credentials/token`; the Rust server reads it at startup.

Select the repositories in `local.observatory_apps`, including repository-only
entries, and grant these repository permissions:

| Permission | Access | Used for |
|---|---|---|
| Metadata | Read (automatic) | Repository access |
| Contents | Read | Stack detection from repository trees and manifests |
| Pull requests | Read | Open PR details |
| Commit statuses | Read | Legacy PR status checks |
| Actions | Read | Deployment/dependency workflow runs, jobs and logs |
| Issues | Read and write | Issue counts and dashboard issue creation |

**Checks API limitation:** GitHub does not offer a Checks permission in the
fine-grained PAT UI and currently lists Checks API access as a
[fine-grained PAT limitation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens-limitations).
Actions read and Commit statuses read are not replacements for Checks access.
If GitHub denies the check-runs request, Observatory shows the PR check status as
**unknown** while retaining the other repository signals. Issue creation still
uses Issues write permission. Full authenticated Checks access with narrowly
scoped permissions requires a GitHub App with Checks read; automatic installation
token generation/refresh is not implemented by Observatory's static-token setup.

The Observatory token does not need Actions variables, Secrets, or Administration
permissions. Keep the Terraform token's existing permissions for provisioning.
Issues must also be enabled on each target repository. Update token repository
access when adding inventory entries, and rotate it before its chosen expiry.
GitHub records the token's account as the issue author; users
submit with their Observatory session and do not authenticate to GitHub.

To roll out [direct issue creation](https://github.com/mucsi96/observatory-app/pull/38):

1. Create the dedicated token with the permissions above and store it as
   `observatory-github-token` in the master Key Vault without committing or logging
   the value. For later rotations, replace this dedicated secret.
2. After explicit operator approval, apply p07 to provision/assign `createIssues`
   and synchronize the runtime source Secret.
3. Deploy the Observatory application change. After token rotation, restart the
   server with `kubectl -n observatory rollout restart deployment/observatory`
   and check `kubectl -n observatory rollout status deployment/observatory`.
   A pipeline rerun with unchanged chart values may not restart the pods.
4. Start a fresh Observatory session and use **Add issue** on an inventory app.
   Confirm creation succeeds and that a session with only `readApps` remains
   read-only. A GitHub permission error requires checking the server token's
   repository access and Issues permission, not a personal GitHub browser login.

Infrastructure was applied with operator approval on 2026-11-04 using
`scripts/create.sh`: 2 resources added, 3 changed, and 0 destroyed. This created
the `createIssues` role ID and owner assignment, updated the API registration and
dedicated runtime token Secret, and persisted the rotated Netcup refresh token.
The enabled Entra role/user assignment and exact runtime Secret match with
`observatory-github-token` were verified without displaying credentials.
Observatory was restarted to load the dedicated token and completed rollout with
1/1 replicas ready. The application change in PR #38 remains to be merged and
deployed; fresh-session issue creation is still an application rollout check.

See the [architecture summary](https://github.com/mucsi96/skeleton-app/issues/105).

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
| `observatory-github-token` | Dedicated Observatory fine-grained PAT: collector read permissions and Issues write access; see [required permissions](#dedicated-observatory-github-token) | [GitHub → Fine-grained personal access tokens](https://github.com/settings/personal-access-tokens) |
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

Each database-backed application definition provisions its own non-administrator
login role and same-named schema. The PostgreSQL module only owns the database
server, while the backup service consumes each application's schema-owner
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

### Automated server updates

The `Update server` GitHub Actions workflow runs every day at 01:00 in the
`Europe/Budapest` timezone, including daylight-saving time changes. It invokes
the Ansible-provisioned `/usr/local/sbin/update-server` helper, which updates the
Twingate connector, Debian packages, kernel and security patches, upgrades k3s
from its stable channel, prunes unused container images, and always schedules a
restart after the update attempt.

Run `scripts/create.sh` after adding the workflow. Terraform grants the existing
GitHub Actions Twingate service account access to the private SSH endpoint,
creates a main-branch OIDC identity, and populates the repository's Azure,
Key Vault, and Twingate Actions secrets. The identity can read only `host`,
`ssh-port`, `ssh-user-name`, and `ssh-private-key` from the platform vault.
Maintenance runs independently under systemd; query `{app="update-server"}` in
Grafana to inspect its logs. The workflow can also be started manually from the
Actions tab.

## Configuration

Netcup identifiers, authentication, and image selection are loaded from Azure
Key Vault; the remaining server settings are hardcoded. The root variables (`environment_name`,
`azure_subscription_id`, `azure_location`, `storage_account_name`) are written
to `backend.tf` by `scripts/init.yaml` during bootstrap.
