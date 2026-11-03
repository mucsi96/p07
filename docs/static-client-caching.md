# Static client caching

The application pipelines own Blob HTTP cache properties. Azure Storage has no
account/container default `Cache-Control`; Terraform owns storage, CORS and upload
permissions, while the shared client charts set document responses to
`private, no-cache, no-store`.

The coordinated application changes cover Skeleton/Hello, Cooking, Library,
Expense Tracker, Observatory, Training Log, PostgreSQL Backup and Learn Language. Each publishes
assets directly to the `assets` container without a release prefix. All assets, including manifests,
icons, fonts and bundles, use `public, max-age=31536000, immutable`.

Relative module, stylesheet and manifest icon references stay in the asset container;
document navigation, manifest start URL/scope/ID, API and telemetry stay on the
application origin.

After preparing the build, deployment deletes every blob in `$web`, then every
blob in `assets`, including any old release directories. It uploads only the latest
assets and publishes `$web/index.html` last with `no-store`. Downtime during this
replacement is intentional. A failed deletion or upload stops deployment; the
site can remain unavailable until a successful deployment. Old bundles are not
retained for open tabs or rollback.

Deleting blobs does not invalidate browser caches. Files whose URLs do not change
can remain cached for one year even after deployment; content-hashed bundles get
fresh URLs when their content changes.

These changes take effect when each application's updated pipeline deploys;
existing blobs are removed on that deployment. No Terraform apply is needed.
Learn Language's migrated static-hosting pipeline follows the same replacement
and cache contract as the other applications.
