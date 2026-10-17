# Stock ForwardAuth: implementation and Hello/Cooking rollout

The reusable implementation spans three platform/application boundaries:

- `k8s-helm-charts/charts/oauth2_proxy_forwardauth`: pinned upstream oauth2-proxy
  dependency, exact OAuth HTTPRoute, standard document/API filter policies and
  Redis sessions. Existing app charts accept generic `routeFilters`.
- `k8s-modules/modules/setup_app_forwardauth`: platform-owned per-app chart release,
  persisted cookie/client/Redis Secrets, exact excluded routes and checksum rollouts.
  The consumed deployment configuration is published to app Azure Key Vaults.
  Hello/Cooking opt in with `forward_auth`; existing callers remain unchanged.
- `skeleton-app` and `cooking-app`: auth-free frontend code and a server-driven
  environment bootstrap. The controller checks the proxy session and returns
  configuration or a generic redirect directive. JWT audience/scope/role and
  exact-Origin validation remain authoritative on APIs.

The stock proxy is used per app; the Rust BFF is not a deployment dependency.
The existing Grafana/Observatory routes are outside this pilot.
The shared module also supports email-header mode for Grafana and login-gate
mode for other protected services, without requiring an application API registration.

## Publication and provisioning order

Published charts: ForwardAuth **4.0.0**, client-app
**23.0.0**, spring-app **31.0.0**, go-app **2.0.0** and rust-app **1.0.0** are
published. Module release **v-89** still pins ForwardAuth **2.0.0** centrally.
The follow-up public-frontend/AKV module changes pin published **4.0.0** and must
be published before the corresponding app cutover. Keep p07 module
refs explicit and published; the operator rollout is paused for review.

1. Publish the chart changes through the chart repository's release workflow.
   Record the actual published `oauth2-proxy-forwardauth`, `client-app`,
   `spring-app` and `go-app` versions. The wrapper builds its locked upstream
   dependency before packaging. No unreleased chart version is activated in p07.
2. Publish the shared module changes. Update p07's explicit published platform
   module refs to that release; retain any independently pinned Observatory
   handoff until that separate migration is reconciled. This implementation does
   not fabricate a release tag or replace published refs with sibling paths.
3. Adapt [the pilot override example](forwardauth-pilot.tf.example). The
   module already pins the published chart. The example can be copied as
   `forwardauth_override.tf`, merging into the existing module calls. Keep
   `retain_spa_redirects = true` for preprovisioning.
4. Review the environment plan. The existing Web-client conversion retains the
   application and service-principal resource addresses/client IDs. During
   preprovisioning both old SPA redirects and the new `/oauth2/callback` Web
   redirect exist. API registrations, roles, workload identities, data/PVCs and
   database credentials are not replaced by this migration. Operator provisioning
   creates the auth releases and enables the Traefik CRD provider.
5. Deploy the pilot server/client builds together. Their scripts require the
   corresponding auth Helm release and middleware-capable app charts before
   deploying. They set `BROWSER_ORIGIN=https://<app-host>` and read the
   `forward-auth-config` JSON from the app's Azure Key Vault. Terraform publishes
   the release name, API filters and private-session/public-login URLs, with
   per-secret deploy read access. The URLs are passed only to backend environment
   variables; frontend code knows no OAuth endpoint names.
   Only the API receives auth filters; client chart values are reset so previous
   frontend auth filters are removed. The policies use standard request/response
   header modifiers and one ForwardAuth ExtensionRef.
   Missing or malformed policies fail the deployment preflight. This is a coordinated
   two-release route/client cutover, not a zero-downtime guarantee for old tabs.
   Existing API-mode installations using document filters must remove those
   frontend references before upgrading the auth chart. Deploy backend bootstrap
   and generic frontend-loader builds together with the exact environment exclusion.
6. Verify owner-only Hello, household Cooking, API roles, Origin rejection,
   renewal after idle and automatic bootstrap redirects after a missing session.
   Check real Gateway HTTPRoute status, anonymous static frontend access and
   absence of frontend auth controls. The automated tests use real containers and a
   confidential OIDC fixture, not real Entra.
7. Set `retain_spa_redirects = false` and provision the final cleanup. This removes
   the SPA redirect type from the same application objects, leaving confidential
   Web clients. Their display names become Hello Web / Cooking Web. The legacy
   internal `register_spa`/output names remain for Terraform address compatibility;
   the clients no longer receive or need SPA client IDs. `spa-client-id` vault
   entries can be retired separately once all consumers are confirmed removed.

No Terraform apply/destroy or live routing change was run while implementing
this work. App/module/chart publication and the operator rollout are still needed.

## Runtime contract

### Standard routing and the remaining authentication extension

The implementation uses standard Gateway API `Gateway` / `HTTPRoute` resources.
Header stripping and cache controls use inline `RequestHeaderModifier` and
`ResponseHeaderModifier` filters. OAuth and machine routes have no Traefik
ExtensionRef. API-token mode needs one API ForwardAuth Middleware. Email-header
and login-gate modes also provide document authentication for protected service
UIs such as Grafana; custom Headers/Chain resources are not created.

Checked 2026-10-15: Gateway API's latest release is v1.6.3; `ExternalAuth`
([GEP-1494](https://gateway-api.sigs.k8s.io/geps/gep-1494/)) is experimental.
p07 runs Traefik v3.7.13 with Gateway API v1.6.1 standard-channel CRDs, whose
filter enum does not include it. Latest Traefik v3.7.14 also lacks the filter in
its [implementation](https://github.com/traefik/traefik/blob/v3.7.14/pkg/provider/kubernetes/gateway/httproute.go#L406-L479).
Upgrading the CRDs alone cannot provide controller support. A fully
implementation-neutral auth call needs a controller implementing ExternalAuth
and verification of stock oauth2-proxy success/cookie semantics.

The auth Helm release owns a non-secret policy ConfigMap. Terraform reads it and
exports one consumed `deployment_config` object, then `setup_app_base` writes
`forward-auth-config` to the app Key Vault. Deploy jobs read its `release_name`,
`route_filters.api`, `session_url` and `sign_in_url`; the last two configure the
backend bootstrap controller. Terraform-managed services consume the document/API
policies directly. The former unused middleware/ConfigMap-name outputs are removed.

Static frontend HTML, bundles and SPA routes have no authentication filters or
Angular route guards. The chart's `excludedRoutes` configures exact path/method
routes to existing backends; Hello/Cooking exclude `GET /api/environment`.
Before Angular starts, the environment controller checks the session through
private `/oauth2/auth`, discards token-bearing response headers and relays cookie
updates. It returns configuration or a server-selected `redirectTo` pointing at
`/oauth2/start` with a validated relative return target.
The frontend loader follows that generic directive; there is no auth service,
auth interceptor, auth route guard, login/logout UI or popup flow. A read-only
profile resource loads token-free userinfo for the header context menu.
External return targets are rejected. Other browser APIs remain session-protected.
For storage-hosted assets, edge routing must continue to send `/api` and
`/oauth2` to the cluster. Storage does not forward those paths itself.

Every mode publishes exact `/oauth2/start`, `/oauth2/callback`, `/oauth2/sign_in`,
`/oauth2/sign_out` and `/oauth2/userinfo` routes. The SPA uses userinfo for header
display data; login and session decisions remain server-side.
`/oauth2/auth` and the static-202 root remain private ForwardAuth targets.
Authentication responses can contain an API access token; do not expose those
handlers through a broad `/oauth2/` public route.

These are stock proxy endpoints. The backend selects `/oauth2/start` when login
is needed. oauth2-proxy then owns the authorization URL, nonce and PKCE state.
`/oauth2/sign_in` is the stock login/error page. Entra redirects to
`/oauth2/callback`, registered by Terraform. The auth chart's exact HTTPRoute
forwards those requests to the proxy. The stock sign-out endpoint stays available,
while the SPA has no sign-out control. Sign-out clears only the local proxy session.
The proxy renews sessions; a new page load re-enters bootstrap after a lost or
unrenewable session, without frontend session handling.

APIs receive the app's `api://<api-client>/api-access` access token. The Graph
`User.Read` scope and ID-token forwarding flags are not used for that contract.
API-mode proxy identity uses signed `sub` and `preferred_username` ID-token
claims; the optional email claim is not needed to fetch a Graph profile.
Frontend static servers do not receive API tokens. The proxy owns renewal and
the browser has only a host-local HttpOnly cookie. Each app has its own persisted
cookie secret/name and confidential client, while Redis is shared.

The default `__Host-<release>` cookie is Secure, HttpOnly and SameSite=Lax.
Supply trusted source CIDRs matching the actual Traefik connection source for
forwarded client-IP metadata. Refresh defaults to five minutes and must stay
below the access-token lifetime.

Unsafe browser requests require exactly the configured `BROWSER_ORIGIN`, even
though Traefik injects a bearer header. CORS/SameSite/login-flow CSRF checks do not
replace that application check. The API JWT and role checks still apply afterward.

## Cooking machine integration

Browser imports use `POST /api/recipes/import` with the session cookie and exact
Origin. Email/background clients must move to:

```text
POST /api/integrations/recipes/import
Authorization: Bearer <Cooking API access token>
```

The request body is unchanged. The chart's `excludedRoutes` list also contains
this integration route. Its platform-owned HTTPRoute matches that exact
path and POST method, bypasses browser ForwardAuth and retains the caller's
Authorization header. The Go handler requires the normal API issuer, audience,
`api-access` and `createRecipe` role; a browser cookie alone is insufficient.
This route is the sole mutation Origin exemption in Cooking. Update any existing
email caller at cutover; the old browser path will require a browser session.

Other apps' bank/device/dictionary/download contracts remain separate later
fleet migration work; do not add a blanket `/api` exemption.

## Development and validation

Use each app's complete test pod as the same-origin authentication entrypoint
(`http://localhost:8150` for Hello, `:8160` for Cooking). The test-only proxy uses
HTTP cookies and disposable credentials; the production chart always uses
Secure host-only cookies. The fixture container is the stock Alpine image so
Podman's in-container wget health probe works. Production uses the normal
upstream image/probes.

Standalone Angular/JVM/Go development also needs a local ForwardAuth entrypoint
that routes `/api` and `/oauth2` and a matching `BROWSER_ORIGIN`; the previous
direct-API plus browser-OIDC setup is no longer an authentication path. For hot
reload, point that gateway's frontend backend at the Angular dev server and
continue browsing through the gateway origin.

Checks include:

- `python3 scripts/check_forwardauth.py` in the chart repo: all token modes,
  exact path/method exclusions, public-route isolation, Secrets,
  rejected incomplete configuration, and
  unchanged legacy app routing with optional filters.
- `terraform fmt -check` and `terraform validate` for the shared and pilot modules.
- Both Angular production builds, Hello's GraalVM native test image, Cooking's
  production Go image, Go build/vet, and shell syntax checks.
- Playwright against isolated actual app/PostgreSQL/AI/Redis/OIDC/Traefik pods:
  18 Hello + 37 Cooking tests passed, covering public HTML/assets, automatic
  bootstrap redirects, safe deep-link restoration, forged-session rejection,
  private/household access, API roles, mutation Origin rejection, server renewal,
  token-free header profile data, stock sign-out, and automatic recovery on the
  next page load.
- Email-header and login-gate browser flows against stock proxy/Redis/Traefik and
  a protected service fixture, with no API registration, passed login, header
  spoof rejection and logout checks.

The local validation runner used distinct pod names/images and removed only its
own pods; existing development pods were not replaced.
