# Expense Tracker gateway/static-hosting cutover

Companion to https://github.com/mucsi96/expense-tracker/issues/59.

`expense_tracker.tf` composes the existing v-102 modules to provision a Web
registration, per-app oauth2-proxy with shared Redis, static website storage,
app-origin Blob CORS and scoped CI upload grants. The application vault exposes
`forward-auth-config` and `client-storage-config`. Logging accepts same-origin
Faro on the expenses hostname.

The exact POST `/api/bank-notifications` route forwards to
`expense-tracker-server:8080` without browser authentication. The server still
requires the existing bank token; the Cloudflare worker, token and edge exclusion
are preserved. Other API paths use chart-owned session authentication and
backend JWT issuer/audience/scope/role validation.

## Rollout order

1. Review and apply this infrastructure PR before deploying the application PR.
   The old SPA registration and its vault client ID remain for the currently
   deployed browser client. The database schema, credentials, API registration,
   workload identity and both retained PVs keep their existing resource addresses.
2. Deploy the application pipeline. It uploads tested assets before index HTML,
   retains earlier bundles and upgrades the existing releases with reset values:
   spring-app 37.0.0 and static-client-app 5.0.0. The latter removes the old client
   Deployment and uses authenticated gateway document routing to Azure.
3. Verify signed-out deep links redirect before scripts load, signed-out API
   requests return 401, signed-in category/settings changes pass CSRF, and a
   missing/invalid bank token returns 401. Check a valid bank notification,
   direct asset CORS, PWA navigation and Faro 202 delivery.
4. Remove the unused SPA registration after the new application is confirmed.
   Keep the Web/API registrations, PostgreSQL data and persistent volumes.

No infrastructure apply or production verification is performed by these PRs.
Terraform validation uses the generated variable declarations from
`scripts/init.yaml` in an ignored local `backend.tf`, without a remote backend.
