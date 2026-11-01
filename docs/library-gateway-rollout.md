# Library gateway/static hosting rollout

Companion to https://github.com/mucsi96/library-app/issues/34.

`library.tf` provisions a confidential Entra Web client, per-app ForwardAuth
session backed by the shared Redis, Azure website/document and Blob asset
storage, app-origin CORS and scoped deployment grants. `main.tf` adds Library
to the same-origin Faro receiver hosts. All reusable modules stay pinned v-102.

1. Review a normal infrastructure plan and apply through the operator workflow.
   The existing API registration/roles, namespace, PostgreSQL schema and login,
   OpenAI secret, workload identity, PVs and backups retain their addresses.
   The legacy SPA registration is retained for the old client during rollout.
2. Confirm `library-forwardauth` is ready and the application vault exposes
   `forward-auth-config` and `client-storage-config` to its deploy identity.
3. Merge/deploy the companion library-app PR. Its pipeline publishes the tested
   assets before index HTML, then installs spring-app 37.0.0 and
   static-client-app 5.0.0 with auth and reset values. It preserves the existing
   `library-app-pvc` and its `/app/storage` mount.
4. Check signed-out document redirects, signed-out API 401, signed-in imports
   (including thumbnails/manual ISBN), status changes, bulk renewal and logout
   session expiry. Check Blob CORS, deep links and `/_telemetry/collect` (202).
5. Remove the legacy SPA registration only after verifying rollout and deciding
   the rollback window is over. Rolling back requires restoring the old app
   chart/client image. The legacy SPA client-id secret remains available until
   that registration is retired.

No infrastructure apply or production changes are part of the implementation.
