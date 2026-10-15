# Per-application stock oauth2-proxy with Traefik ForwardAuth

Investigation: 2026-10-15.

The chart, shared modules and Hello/Cooking pilot are now implemented locally.
See [implementation and staged rollout](forwardauth-rollout.md) for the
publication handoff and SPA-redirect cleanup; the environment is not activated.
The implementation now uses standard HTTPRoute header filters and only two
Traefik ForwardAuth resources; see the rollout guide's standard API support notes.

## Recommendation

Use one stock oauth2-proxy instance per application, attached to the existing
Traefik Gateway API routes through ForwardAuth middleware. Reuse the platform
Redis instance and retain each application's API audience, scopes, roles and
workload identity.

A new chart is useful for packaging the platform integration, but is not a
technical requirement. The upstream `oauth2-proxy` chart already supports
`gatewayApi`, `networkPolicy`, existing credential/Redis Secrets and templated
`extraObjects`. Rendering those features together was verified.

Recommended chart location in `k8s-helm-charts`:

```text
charts/oauth2_proxy_forwardauth/
  Chart.yaml                 # name: oauth2-proxy-forwardauth
  Chart.lock
  values.yaml
  values.schema.json
  templates/
    middleware.yaml
    route-filters.yaml         # ConfigMap with standard HTTPRoute filter policies
    oauth-route.yaml
  README.md
```

Use the upstream chart as a pinned dependency for its Deployment, Service,
configuration, probes and proxy NetworkPolicy. Keep our chart focused on the
Middleware and public OAuth routing contract. Pin upstream chart `10.4.3` /
image `v7.15.2` as the investigated baseline; evaluate upgrades separately.
The chart should support API-token, email-header and login-gate modes.

The release workflow currently enumerates chart/version prefixes explicitly.
Add the new prefix and version-update entry, and build the pinned dependencies
before packaging. Add a render check for each supported mode and rejected
incomplete configurations.

## Request paths

```text
Browser -> Cloudflare -> Traefik -> existing frontend/API Service
                            |
                            +-> per-app oauth2-proxy -> Redis
                                        |
                                        +-> Entra during login/renewal
```

Traefik forwards application bodies and responses directly. ForwardAuth adds a
separate authentication request; it does not reduce request count relative to
the current direct bearer-token APIs. Keep `forwardBody: false` so uploads and
streams do not pass through the auth service.

Provide two middleware entry points:

| Target | Proxy endpoint | Unauthenticated behavior |
| --- | --- | --- |
| Frontend/document routes | `/`, with a static `202` upstream | Start login; JSON-accepting requests can receive `401` |
| API routes | `/oauth2/auth` | `401` without a login redirect; authorization can return `403` |

The static response must not point back to the application's public hostname.
The proxy is an authentication service, not a second application router.
Do not apply a blanket `401-403` Errors middleware: it would turn API failures
and genuine authorization denials into browser login responses.

Restrict forwarding metadata to trusted Traefik callers and configure its
ForwardAuth/header handling consistently with the existing Cloudflare-aware
entrypoint. Propagate the app's session/CSRF cookies through
`addAuthCookiesToResponse`, including cookie clearing on failed authentication.
Do not copy credential-bearing auth response headers to browser responses.

## API-token contract

For applications with existing resource-server APIs, request:

```text
openid profile email offline_access api://<application-api-client-id>/api-access
```

Do not append Microsoft Graph `User.Read` to the app API resource scopes. Each
proxy needs the access token for its own API. The existing `register_webapp`
helper used by Grafana only grants Graph permissions and needs an API-scope/
consent path for this use.

In the alpha configuration, return the access token to the private ForwardAuth
caller:

```yaml
injectResponseHeaders:
  - name: Authorization
    values:
      - claimSource:
          claim: access_token
          prefix: "Bearer "
upstreamConfig:
  upstreams:
    - id: forwardauth
      path: /
      static: true
      staticCode: 202
```

Traefik's API middleware copies `Authorization` into the backend request. Clear
caller-supplied bearer and identity headers before authentication. The API
continues validating signature, issuer, audience, `api-access` and endpoint roles.
The usual `set-authorization-header`/`pass-authorization-header` options select
an ID token, which is not an app API access token.

For Grafana, return `X-Auth-Request-Email` from the authenticated email claim
instead. A login-gate-only service needs no API token forwarding. Preserve
ordinary application cookies, such as playback cookies and external OAuth
session state; removing the entire Cookie header would break those contracts.

## Public OAuth endpoints

Publish only the control/identity paths needed by the client:

- `/oauth2/start`
- `/oauth2/callback`
- `/oauth2/sign_in`
- `/oauth2/sign_out`
- `/oauth2/userinfo`

Use exact HTTPRoute matches, rather than forwarding all of `/oauth2/` to the
proxy. A successful `/oauth2/auth` response carries the API access token in its
headers under the proposed configuration. Exposing that handler directly would
make those credentials browser-readable. The internal static-202 endpoint
must also have no public route to the proxy.

`/oauth2/userinfo` supplies token-free identity for the frontend. Clients must
use stock endpoint names and response fields, rather than the custom BFF's
`/oauth2/session` and `POST /oauth2/logout` interface. Local sign-out uses
`/oauth2/sign_out`; it clears that app's session, not the Entra SSO session.
Navigating straight back to a protected document can immediately start login.

## Sessions and access policies

- Use a confidential **Web** redirect at each app's `/oauth2/callback`, with a
  server-held client secret. Remove SPA-typed redirects/browser OAuth during
  that app's migration. Existing client objects can be converted in place.
- Keep API registrations and their Kubernetes federated identities. They also
  own application roles and Azure runtime permissions.
- Require Web-app assignment: owner access for private apps, household access
  for Cooking. Preserve the API role assignments independently.
- Use a distinct persisted cookie secret and cookie name per app, preferably
  `__Host-<app>` with Secure, HttpOnly, Path=/, SameSite=Lax and no Domain.
- Redis sessions keep OAuth tokens server-side. Unique cookie names also
  prefix stored session tickets; reuse the platform Redis rather than deploy
  a Redis subchart per app. Shared Redis credentials are not per-app ACL isolation.
- Keep tokens in the stored session; `session_cookie_minimal` is inappropriate
  when forwarding access tokens or refreshing them.
- Set a nonzero refresh interval below the API access-token lifetime. Stock
  refresh is age-based, rather than the custom BFF's expiry-skew policy.
- Explicitly enable S256 PKCE and nonce verification for the OIDC provider.
- If email-file restrictions are used, omit the wildcard email-domain allowance:
  those are alternative allow mechanisms, not cumulative restrictions.

## Required CSRF protection

Stock ForwardAuth checks the session but does not enforce the original
application request's Origin. Its OAuth callback CSRF checks protect login,
not application mutations.

The isolated test confirmed that a real browser form on one sibling app can
POST to another app with its session cookie and receive a successful API
response. SameSite=Lax does not isolate sibling hosts on the same site.

Before a browser app switches to cookie authentication, implement an exact
configured-Origin check for its unsafe methods, or explicit CSRF-token
validation. Reassess Spring's resource-server CSRF behavior: after ForwardAuth
injects a bearer token, the backend cannot assume that the original browser
request supplied that token deliberately. CORS response headers alone do not
prevent the mutation. Separately authenticated machine routes keep their own
contracts and must not require a browser Origin.

## Ownership and integration changes

| Owner | Responsibility |
| --- | --- |
| `p07` / `k8s-modules` | Web registrations, API consent, assignments, persisted credentials, per-app auth chart release, shared Redis configuration, platform route exceptions |
| Auth chart | Stock proxy dependency, proxy access policy, standard filter policies, two ForwardAuth resources and exact public OAuth routes |
| App charts | Render generic HTTPRoute `routeFilters` supplied from the auth release's non-secret ConfigMap |
| App repositories | Cookie-based browser auth integration, user-info/logout UX, Origin/CSRF protection and app integration tests |

Keep the auth release Terraform-owned, matching the existing platform proxy
ownership. App deploy jobs then need no access to client/cookie/Redis secrets
and no additional `traefik.io` write permissions just to reference middleware.

Enable `providers.kubernetesCRD` in `setup_ingress_controller`: it is currently
disabled, and Traefik requires it for Middleware HTTPRoute ExtensionRefs. Keep
the Gateway API provider enabled. Extend the application route templates with
standard `routeFilters`; the default empty list preserves existing routes.

The upstream chart restricts proxy ingress to Traefik. The pilot APIs retain
their JWT, scope, role and Origin checks. The existing chart release/deployment
ownership remains explicit.

Preserve specific non-browser contracts with more-specific platform routes:

| App/service | Separate contract |
| --- | --- |
| Expense Tracker | `POST /api/bank-notifications`, worker bearer token |
| Learn Language | `/api/dictionary`, `/api/known-cards`, application API tokens |
| Training Log | `/api/reading/koreader-sync`, `/api/device/books/**`, device credentials |
| Training Log | `/api/strava/authorize`, `/api/withings/authorize`, existing external OAuth flow |
| Backup | `/api/download/{token}`, existing one-time download token semantics |
| Faro | Browser telemetry ingestion, separate from interactive application login |

Media/playback and download routes need explicit integration tests before
choosing whether an extra browser-session gate preserves their intended use.
Do not make all of `/api` anonymous. Keep matching sensitive to the actual
host, path and method contract.

## Verification performed

An isolated Podman/Chromium fixture used two unmodified stock oauth2-proxy
v7.15.2 containers, real Traefik v3.7.13, real Redis, the existing confidential
mock OIDC provider and separate frontend/backend mocks. Each API mock verified
JWT signature, issuer, its own audience, scope and role. Proxy configuration was
rendered from the upstream Helm chart, with only the second instance's listener
port adapted for the shared-pod test network.

Verified:

- Upstream chart rendering of exact OAuth HTTPRoutes, Middleware extraObjects
  and NetworkPolicies.
- Browser login with S256 PKCE and return to the original path/query.
- Secure, HttpOnly, host-local session cookies.
- API `401` without redirects and successful app-specific access-token forwarding.
- Replacement of caller-supplied Authorization headers.
- Token-free browser API/user-info responses and no public route to AuthOnly.
- Separate app sessions and rejection of another app's session cookie.
- Preserved POST bodies, streaming and WebSockets.
- Eight concurrent API requests succeeding after access-token expiry/renewal.
- Local sign-out deleting its Redis session while the other app remains logged in.
- The missing mutation Origin check, including a real sibling-origin form POST.

This verifies the stock ForwardAuth contract and chart rendering. Kubernetes
Gateway/Middleware resource acceptance, NetworkPolicy enforcement, real Entra
consent/assignment/renewal, and the real applications' integrations remain pilot
verification. It is not a latency or memory benchmark. No live registrations or
routes were changed.

Implement the reusable chart/platform integration first, then migrate Hello
and Cooking to exercise private and household policies before the remaining apps.

## References

- [Upstream Traefik integration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/integrations/traefik)
- [Upstream chart 10.4.3 values](https://github.com/oauth2-proxy/manifests/blob/oauth2-proxy-10.4.3/helm/oauth2-proxy/values.yaml)
- [Alpha header configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/alpha-config)
- [Traefik ForwardAuth](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/forwardauth/)
- [Middleware HTTPRoute filters](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/#using-traefik-middleware-as-httproute-filter)
