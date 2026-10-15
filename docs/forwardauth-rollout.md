# Stock ForwardAuth: implementation and Hello/Cooking rollout

The reusable implementation spans three platform/application boundaries:

- `k8s-helm-charts/charts/oauth2_proxy_forwardauth`: pinned upstream oauth2-proxy
  dependency, exact OAuth HTTPRoute, standard document/API filter policies and
  Redis sessions. Existing app charts now accept generic `routeFilters`.
- `k8s-modules/modules/setup_app_forwardauth`: platform-owned per-app chart release,
  persisted cookie/client/Redis Secrets and checksum rollouts.
  Hello/Cooking opt in with `forward_auth`; existing callers remain unchanged.
- `skeleton-app` and `cooking-app`: browser OAuth libraries/interceptors removed,
  token-free `/oauth2/userinfo`, local logout, popup reauthentication preserving
  mounted forms, and backend exact-Origin protection. JWT audience/scope/role
  validation remains authoritative.

The stock proxy is used per app; the Rust BFF is not a deployment dependency.
The existing Grafana/Observatory routes are outside this pilot.

## Publication and provisioning order

Chart publication completed on 2026-10-15: ForwardAuth **1.0.0**, client-app
**23.0.0**, spring-app **31.0.0**, go-app **2.0.0** and rust-app **1.0.0** are
published. The shared ForwardAuth module pins 1.0.0 centrally; its caller input
does not contain a chart-version placeholder. The module release/p07 ref update
and operator provisioning still follow review.

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
   deploying. They set `BROWSER_ORIGIN=https://<app-host>` and read document/API
   JSON filter policies from `<app>-oauth2-proxy-route-filters`. The policies use
   standard request/response header modifiers and one ForwardAuth ExtensionRef.
   Missing or malformed policies fail the deployment preflight. This is a coordinated
   two-release route/client cutover, not a zero-downtime guarantee for old tabs.
6. Verify owner-only Hello, household Cooking, API roles, Origin rejection,
   renewal after idle, cookie clearing and popup reauthentication. Check the
   real Gateway HTTPRoute status and the chart-owned proxy NetworkPolicy. The
   automated tests use real containers and a confidential OIDC fixture, not real Entra.
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
ExtensionRef. Only the document/API authenticators use two ForwardAuth
Middleware resources; custom Headers/Chain resources are not created.

Checked 2026-10-15: Gateway API's latest release is v1.6.3; `ExternalAuth`
([GEP-1494](https://gateway-api.sigs.k8s.io/geps/gep-1494/)) is experimental.
p07 runs Traefik v3.7.13 with Gateway API v1.6.1 standard-channel CRDs, whose
filter enum does not include it. Latest Traefik v3.7.14 also lacks the filter in
its [implementation](https://github.com/traefik/traefik/blob/v3.7.14/pkg/provider/kubernetes/gateway/httproute.go#L406-L479).
Upgrading the CRDs alone cannot provide controller support. A fully
implementation-neutral auth call needs a controller implementing ExternalAuth
and verification of stock oauth2-proxy success/cookie semantics.

Application deploy jobs consume a non-secret filter ConfigMap owned by the auth
Helm release. This centralizes the ordered policies without duplicating JSON in
each app repo or granting the deploy job new auth-secret requirements.

Only exact `/oauth2/start`, `/oauth2/callback`, `/oauth2/sign_in`,
`/oauth2/sign_out` and `/oauth2/userinfo` routes reach the public proxy handler.
`/oauth2/auth` and the static-202 root remain private ForwardAuth targets.
Authentication responses can contain an API access token; do not expose those
handlers through a broad `/oauth2/` public route.

APIs receive the app's `api://<api-client>/api-access` access token. The Graph
`User.Read` scope and ID-token forwarding flags are not used for that contract.
API-mode proxy identity uses signed `sub` and `preferred_username` ID-token
claims; the optional email claim is not needed to fetch a Graph profile.
Frontend static servers do not receive API tokens. The proxy owns renewal and
the browser has only a host-local HttpOnly cookie. Each app has its own persisted
cookie secret/name and confidential client, while Redis is shared.

The default `__Host-<release>` cookie is Secure, HttpOnly and SameSite=Lax.
The chart-owned proxy NetworkPolicy admits Traefik from `kube-system`. Supply
trusted source CIDRs matching the actual Traefik connection source. Refresh
defaults to five minutes and must stay below the access-token lifetime.

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

The request body is unchanged. The platform-owned route matches that exact
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
  public-route isolation, Secrets, rejected incomplete configuration, and
  unchanged legacy app routing with optional filters.
- `terraform fmt -check` and `terraform validate` for the shared and pilot modules.
- Both Angular production builds, Hello's GraalVM native test image, Cooking's
  production Go image, Go build/vet, and shell syntax checks.
- Playwright against isolated actual app/PostgreSQL/AI/Redis/OIDC/Traefik pods:
  login, token-free browser identity, private/household access, API roles,
  mutation Origin rejection, renewal, logout and preserved recipe drafts.

The local validation runner used distinct pod names/images and removed only its
own pods; existing development pods were not replaced.
