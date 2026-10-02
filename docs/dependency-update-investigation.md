# Dependency-update investigation — 2026-10-02

## Findings

The 2026-09-28 scheduled GitHub Actions runs were green, but six applications
aborted before opening their dependency PR:

| Repository | Run | Result |
| --- | --- | --- |
| skeleton-app | [36380891768](https://github.com/mucsi96/skeleton-app/actions/runs/36380891768) | Aborted |
| learn-language | [36380737140](https://github.com/mucsi96/learn-language/actions/runs/36380737140) | Aborted |
| training-log-pro | [36381067703](https://github.com/mucsi96/training-log-pro/actions/runs/36381067703) | Aborted |
| library-app | [36380774965](https://github.com/mucsi96/library-app/actions/runs/36380774965) | Aborted |
| cooking-app | [36380911405](https://github.com/mucsi96/cooking-app/actions/runs/36380911405) | Aborted |
| postgres-azure-backup | [36380692193](https://github.com/mucsi96/postgres-azure-backup/actions/runs/36380692193) | Aborted |
| expense-tracker | [36381156830](https://github.com/mucsi96/expense-tracker/actions/runs/36381156830) | PR created |
| p07 | [36380991197](https://github.com/mucsi96/p07/actions/runs/36380991197) | PRs 38 and 39 updated |

The six aborted runs shared this sequence:

1. The all-dependencies group selected TypeScript 7.0.2 alongside Angular 22.2.0.
   Angular's compiler/build packages require TypeScript `>=6.0 <6.1`, so npm
   failed to generate `client/package-lock.json` with `ERESOLVE`.
2. Renovate tried to publish the `renovate/artifacts` failure status, but the
   workflow token lacked `statuses: write`. GitHub returned HTTP 403 with
   `Resource not accessible by integration` and `statuses=write` in the accepted
   permissions header.
3. Renovate 42.99.0 reported `Caught error setting branch status - aborting`
   and classified the repository result as `repository-changed`. It exited
   successfully without reaching PR creation. A green workflow alone therefore
   did not establish that updates had been proposed.

Cooking also had `can_approve_pull_request_reviews: false`, which prevents
`GITHUB_TOKEN` from creating PRs even with job-level `pull-requests: write`.
That repository setting was enabled and read back successfully on 2026-10-02.
The other six application repositories already had it enabled.

Observatory currently has no `Update dependencies` workflow; it is not one of
the silently aborted runs.

## Fixes

- Add `statuses: write` to the seven application updater workflows and p07's
  updater. Keep this permission scoped to the updater job.
- Constrain Renovate's TypeScript updates in `client/package.json` to
  `>=6.0 <6.1` in all seven applications, including the skeleton template.
  Other TypeScript consumers (tests and mock servers) retain their existing
  update policy. Review this constraint when upgrading Angular.
- Enable Actions PR creation for Cooking in repository settings.

Application repositories own these workflows and Renovate configurations;
p07 provisioning does not generate them. No Terraform apply is needed.

## Validation and rollout

- Renovate 42.99.0's configuration validator accepted all seven updated configs.
- The npm registry confirmed Angular compiler-cli 22.2.0's TypeScript peer range.
- For each of the six affected repositories, fetched the current
  `renovate/all` client manifest into a temporary directory, changed only
  TypeScript from 7.0.2 to 6.0.3, and ran
  `npm install --package-lock-only --no-audit --ignore-scripts`.
  All six generated lockfiles successfully, without bypassing peer checks.

The workflow/configuration fixes must reach each repository's default branch
before scheduled runs use them. Then dispatch `Update dependencies` and verify
the PR, its lockfile, and `renovate/artifacts` status rather than relying only on
the Actions conclusion. Live PR creation with the revised workflows has not yet
been verified.
