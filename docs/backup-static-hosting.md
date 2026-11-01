# Backup gateway and static hosting cutover

The backup application adopts Skeleton issue #105 using existing v-102 building
blocks. Application code and pipeline changes live in `postgres-azure-backup`.

## Infrastructure

- `backup.tf` changes the existing SPA registration into a confidential Web
  registration with `/oauth2/callback`. Explicit moved blocks preserve its
  application, service principal, shared Microsoft Graph reference and grants.
  The Web module restricts login to the assigned owner and creates a proxy secret.
- `backup_forward_auth` provisions per-app oauth2-proxy with the existing shared
  Redis and gateway, publishing `forward-auth-config` to the backup vault.
- `backup_client_storage` creates a separate website/assets account with exact
  backup-origin CORS and container-scoped upload grants for the existing deploy
  identity. Its descriptor is `client-storage-config`.
- Logging adds the backup host's exact `/_telemetry/collect` route with the
  shared collector's credential stripping, origin and rate-limit controls.
- No `client-runtime-config` or response-body injection is introduced.

Backup database credentials, `dbs-config`, the private `ibari/backups` container,
its API storage grant and all existing PV/PVCs retain their current definitions.

## Coordinated rollout

1. Review a fresh infrastructure plan. Expect static storage, proxy/session,
   deployment-secret/read-grant and Web credential/assignment additions, plus
   in-place registration/grant updates and the Faro route. Verify the moved
   resources are not recreated and that no database, backup container or volume
   is deleted/replaced. Validation alone does not establish the plan's result.
2. Provision infrastructure through the operator's approved process. The SPA-to-Web
   change retires the previous browser redirect URI: coordinate it with the app
   rollout and allow a brief login interruption. Keep the moved blocks until all
   applicable environments have migrated.
3. Run the app pipeline: it uploads tested assets first and index last, deploys the
   API with JWT/role checks and CSRF, and upgrades the existing client release to
   static-client-app 5.0.0 using `--reset-values`. This removes only client workload
   resources; the server release keeps its existing PVC definitions.
4. Verify signed-out documents redirect to login, signed-out APIs return 401,
   signed-in database lists and deep links load, and a controlled test backup,
   authorized download and restore succeed. Verify CSRF rejection for mutations
   without a matching token, same-origin telemetry delivery, asset CORS and all
   existing PVCs remaining Bound. Production restore checks require suitable test data.

Frontend settings now require rebuilding the client. The profile endpoint is
read-only data; OAuth and session-flow tests belong to the shared platform suite.
App E2E tests mock gateway identity and retain real backend JWT, role and CSRF
validation. No infrastructure apply has been performed as part of this change.

## Validation — 1 November 2026

- Terraform initialized with the backend disabled and validated using temporary,
  value-free declarations for the normally generated bootstrap variables.
- Published Spring 37.0.0 and static-client 5.0.0 charts rendered with the deploy
  script's values. The server retains all three named PVCs and bound volume names;
  the static client renders no Deployment or PVC.
- The app's native test image built successfully; all 52 container-backed
  Playwright tests and 31 client unit tests passed. Separate-origin browser checks
  passed for Blob-style assets/fonts, read-only profile and same-origin Faro.
- A live Terraform plan, infrastructure apply and production verification remain
  pending. Local checks do not verify live resource replacement behavior.
