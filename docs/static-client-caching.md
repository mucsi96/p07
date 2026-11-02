# Static client caching

The application pipelines own Blob HTTP cache properties. Azure Storage has no
account/container default `Cache-Control`; Terraform owns storage, CORS and upload
permissions, while the shared client charts set document responses to
`private, no-cache, no-store`.

The coordinated application changes cover Skeleton/Hello, Cooking, Library,
Expense Tracker, Observatory, Training Log and PostgreSQL Backup. Each publishes
assets to `assets/releases/<github-run-id>-<github-run-attempt>/` and prepares
document links against that directory. All those assets, including manifests,
icons, fonts and bundles, use `public, max-age=31536000, immutable`.

Relative module, stylesheet and manifest icon references stay within the release;
document navigation, manifest start URL/scope/ID, API and telemetry stay on the
application origin. A rerun gets a new directory even if its source commit is
unchanged. This avoids freezing unversioned filenames for a year.

Assets upload first; `$web/index.html` is replaced last with `no-store`. Old asset
directories are retained for open tabs and rollback. Do not overwrite an old
release with different content or delete old assets during deployment.

These changes take effect when each application's updated pipeline deploys;
existing blobs are not retroactively modified. No Terraform apply is needed.
Learn Language's current `main` still deploys a container client, so it has no
Blob upload pipeline to change. Its client chart supplies the document policy
and its nginx configuration already caches static resources for one year. Adopt
the release-directory contract when migrating that app to Blob hosting.
