# UI authentication rollout status — 20 October 2026

## v-94 provisioning — 23 October 2026

Module MR #146 merged and published as **v-94**, commit
`28e1e70b0d5ad23efea67cf10afed4dc470ddac0`. Cooking and Observatory now pin this
release. Observatory receives the standard ForwardAuth inputs and dedicated app
vault; the logging route includes its hostname alongside Hello and Cooking.

The operator explicitly requested running `scripts/create.sh`. Initialization,
configuration validation and the review plan succeeded. The plan preserves
database/storage and server resources, and moves Observatory's shared Graph
principal from the SPA address to the Web address. Deletions are limited to the
old app-specific SPA resources and obsolete platform-vault deploy permission.
The create-script execution and post-apply validation are in progress.

## Application migration follow-up — 23 October 2026

Skeleton has since deployed client-app 24.0.0 and spring-app 32.0.0 with proxy
6.0.0. Live routing, unauthenticated redirects/API rejection, static bundles and
same-origin Faro delivery to VictoriaLogs were verified. Earlier Hello status
below describes the infrastructure-first checkpoint, not this completed rollout.

Cooking migration: https://github.com/mucsi96/cooking-app/pull/29.
Supporting modules: https://github.com/mucsi96/k8s-modules/pull/146.
Cooking's full container E2E suite passed (32 tests). Observatory retains its
Rust/React stack and is moving to separate API/client images and shared charts.

After module MR #146 releases, pin its actual published release for Cooking and
Observatory. Do not guess the next version. The p07 follow-up must:

- In `dashboard.tf`, replace `kubeconfig_secret_id` with
  `k8s_oidc_config = azurerm_key_vault_secret.k8s_oidc_config.value`, add
  `azure_location = var.azure_location` and `forward_auth = local.app_forward_auth`.
- Set Observatory's `client_log_url` to its HTTPS host plus
  `module.setup_victoria_logs.faro_client_path`.
- Add the Observatory hostname to the existing logging module's
  `faro_client_hostnames` so POST/OPTIONS telemetry reaches the collector.
- Review the plan's Graph principal state moves, app-specific registration
  replacement, dedicated app vault and namespace RBAC; obtain explicit approval
  for any new apply. Preserve all database/storage and shared Graph objects.
- Provision those contracts before merging/deploying the app migrations.

Current module pins remain explicit published references. This follow-up records
the dependency and caller changes; it performs no additional infrastructure apply.

## Applied infrastructure — 23 October 2026

The operator explicitly authorized infrastructure-first rollout with temporary
application downtime and recreation of app-specific Entra resources. The full
`scripts/create.sh` was run from this branch after Docker authentication.

Before applying, Cooking's Microsoft Graph service-principal state entry was
moved from `module.setup_cooking_app.module.setup_cooking_spa.azuread_service_principal.msgraph`
to `module.setup_cooking_app.module.setup_cooking_web[0].azuread_service_principal.msgraph`.
Both refer to the same shared principal; it was preserved, not recreated.

The first apply performed the infrastructure changes but returned errors for
three already-removed Entra objects. A refreshed script rerun completed successfully
(0 added, 2 changed, 1 destroyed). Post-apply planning found only the expected
Netcup refresh-token secret rotation (0 added, 1 changed, 0 destroyed); that saved
plan was applied to persist the refreshed token. No server provisioning changes
or database/storage deletions were present in the reviewed plan.

Verified live:

- Both per-app proxies are deployed at chart **6.0.0**, with one ready replica.
- Traefik is ready at its observed desired generation with rewritebody **v0.3.1**.
- Both app deploy roles can manage Middleware; both vaults publish the new `.auth`
  descriptor. Hello's separate inline runtime configuration is present.
- The two-host same-origin Faro HTTPRoute is accepted with resolved references.
- The shared Microsoft Graph service principal still exists.

Application rollout is **not complete**. Hello still runs client-app 23.0.0 and
spring-app 31.0.0; its API HTTPRoute references the now-removed
`hello-oauth2-proxy-api` middleware. Cooking still runs client-app 22.0.0 and
go-app 1.0.0 with no app-owned auth middleware. Ready pods do not mean these old
apps work with the new infrastructure. Deploy the updated app MRs next.

The inherited Observatory infrastructure migration was also applied: its old
proxy and Terraform-owned route were removed and its direct-JWT registrations
and deployment configuration provisioned. Its matching app rollout remains
separate from this infrastructure validation.

Earlier pre-apply blockers below are retained as historical context; Docker
authentication, shared Graph state ownership and Entra cleanup are now resolved.

## Target configuration update — 23 October 2026

Published modules `v-93` are now selected for Hello (Skeleton), Cooking, ingress
and logging. Both app modules select proxy chart **6.0.0**, export `.auth` and
grant namespace-scoped Middleware deployment permissions. Ingress enables
rewritebody v0.3.1; logging serves exact POST/OPTIONS `/_telemetry/collect` routes
on both application hosts. Each app's log URL is composed from its own hostname
and the logging module's `faro_client_path` output.

Hello's module supplies `client-runtime-config` for the new inline bootstrap.
Cooking's v-93 module still supplies backend bootstrap URLs and `client-log-url`;
it does **not** publish inline `client-runtime-config`. Cooking's application
migration is therefore a separate prerequisite, not completed by these p07 refs.
Cooking's current main deployment script does not yet consume `.auth` or clear
old Helm values. Do not deploy it unchanged as the chart-6 consumer.

### Required cutover before applying this target

1. Provision plugin, same-origin collector routes, namespace permissions, proxy
   descriptors and fixed `__Host-session` cookies while retaining proxy chart 5.
   The module implementation at `8dccfa3a79faf1fc8c4a4ac88e038917cc725835` records
   the preparatory contract; it is not a published release pin for this p07 target.
2. Deploy compatible Hello and Cooking builds using app-owned authentication
   middleware and reset legacy Helm `routeFilters` values. Preserve Cooking's
   independently authenticated recipe-import exclusion, backend JWT/roles and
   mutation CSRF protection. Coordinate Hello's environment-bootstrap removal.
3. Verify no live HTTPRoutes reference legacy proxy-owned middleware, and that
   Cooking no longer needs SPA redirect coexistence. v-93 removes that old input
   and can retire the old SPA registration; inspect the registration/state
   transition before applying. Never delete a shared Graph principal.
4. Only then apply the v-93 app-module target, which upgrades both proxies to
   chart 6 and removes legacy policy resources.

No infrastructure apply is part of this configuration update. Other modules
retain their saved v-92 pins, and Observatory's independent commit pin and
`reinstall_generation = "initial"` are preserved.

The remainder of this document is the historical 20 October snapshot, not the
current target configuration.

### Live pre-apply verification — 23 October 2026

After operator authorization, dependencies and the Azure backend were initialized
and the create script's setup/plan phase was executed. Apply was not invoked.
The stored backend configuration lacked `azure_tenant_id`; a local ignored
declaration and the authenticated Azure CLI tenant supplied that input.

The plan failed on Docker provider authentication (`empty username found in
store`). Its incomplete summary was 24 additions, 31 changes and 17 deletions;
this is not an approved or complete execution plan. It includes deletion of
Cooking's tracked shared Microsoft Graph service principal and the inherited
Observatory proxy/registration/route migration. Resolve shared-principal state
ownership and scope the Observatory migration before retrying any apply.

Live read-only checks confirmed:

- Hello: client-app 23.0.0, spring-app 31.0.0, proxy chart 5.0.0. Its server
  HTTPRoute still references `hello-oauth2-proxy-api`, which chart 6 removes.
- Cooking: client-app 22.0.0, go-app 1.0.0, proxy chart 5.0.0. Its client and
  server HTTPRoutes have no authentication Middleware references.

The required app-first cutover has therefore not happened. Running the full
auto-apply script against this target now would not meet the intended rollout
contract. No infrastructure apply or state-ownership change was performed.

This branch records the previously authorized rollout configuration and Netcup
authentication retry improvements. It does not activate the pending UI hosting
design or authorize a new infrastructure apply.

## Recorded configuration

- Platform modules and Hello: published modules **v-92**, auth chart **5.0.0**.
- Cooking: intentionally **v-91**, with `retain_spa_redirects = true` until its
  separate app cutover. Its auth proxy also uses chart 5.0.0.
- Hello uses its dedicated confidential Web registration. The old Hello browser
  SPA registration was retired during the earlier authorized provisioning.
- Traefik's Middleware provider is enabled; shared Redis and Gateway inputs are
  passed through `local.forwardauth_pilot`.
- Preserve the independent Observatory module pin
  `4dd25c137fb284c95336b0d16bbc273854274e5e` and `reinstall_generation = "initial"`.

## Pending design

Source of truth: [Skeleton issue #105](https://github.com/mucsi96/skeleton-app/issues/105).
Chart work: [PR #22](https://github.com/mucsi96/k8s-helm-charts/pull/22).
Module and Skeleton source branches: `feat/gateway-spa-index-bootstrap`.

Keep one oauth2-proxy per app. App charts own authentication middleware/header
policies from a simple proxy reference (`auth`). The client chart owns root SPA
routing, nested-path rewriting and inline public runtime configuration. All app
hosts use fixed host-only `__Host-session`; secrets/registrations remain per-app.
The new charts remove manual filter lists and the proxy-owned policy ConfigMap.

After verified releases exist, the p07 composition needs:

- New ingress module with `enable_index_config = true`; wait for the pinned
  rewritebody v0.3.1 plugin/controller rollout.
- New logging module with `faro_client_hostnames` containing Hello's hostname.
- Hello's `client_log_url` set to its own HTTPS hostname plus the logging
  module's `faro_client_path` (`/_telemetry/collect` by default).
- The new Hello module supplying `forward-auth-config.auth`, separate
  `client-runtime-config` and namespace-scoped Middleware deployment permissions.

The pending module deliberately still pins chart 5.0.0 and sets its cookie name
to `__Host-session` for a staged cutover (users sign in again). Deploy app-owned
middleware and remove legacy Helm filter settings **before** upgrading the auth
chart that deletes old middleware. Coordinate the removal of the old environment
bootstrap with the new client/server build; do not assume old tabs continue to
work throughout that transition.

## Operational boundaries

- No new module tag/chart version should be guessed. No apply/destroy/reinstall
  without explicit operator authorization; obey AGENTS.md.
- The live provisioning checkout contains unrelated automation/documentation
  work. Preserve it; this branch stages only the reviewed auth rollout changes.
- Never commit state, plans, kubeconfigs, credentials or provider cache files.
- During old registration cleanup, shared Microsoft Graph tracking was removed
  from one obsolete state address rather than destroying the shared principal.
  Do not destroy a shared Graph principal even if a provider resource uses
  `use_existing = true`.
- Earlier `docs/forwardauth-rollout.md` / pilot examples describe superseded
  environment-bootstrap steps. Use issue #105 and the saved Skeleton handoff.
