# Application infrastructure ownership migration

p07 now owns application-specific infrastructure as top-level Terraform files.
The definitions were transferred from the published `k8s-modules` **v-101**
release, which was already pinned by p07. Reusable modules remain pinned to that
same release; this migration does not require a new module release.

| Former module | p07 definition |
| --- | --- |
| `setup_hello_app` | `hello.tf` |
| `setup_cooking_app` | `cooking.tf` |
| `setup_library_app` | `library.tf` |
| `setup_learn_language_app` | `learn_language.tf` |
| `setup_training_log_app` | `training_log.tf` |
| `setup_expense_tracker_app` | `expense_tracker.tf` |
| `setup_app_dashboard` | `observatory.tf` |
| `setup_backup_app` | `backup.tf` |
| `setup_bank_email_worker` | `bank_email_worker.tf`, `workers/bank-email.js` |
| `setup_party_app` | `party.tf.disabled` |

## State and compatibility

The migration was applied to live p07 with 98 temporary move declarations,
relocating 458 resource instances to their root addresses. Child module moves
preserved their descendants, including database passwords, schema initialization
actions, deployment identities, namespaces and auth sessions. Resource moves
preserved existing volumes, app vault secrets, random encryption keys, bank
notification tokens, and assignments. Cooking's counted Web/SPA/ForwardAuth
module instances retained their indexes.

The approved apply completed with **0 additions, 1 update, 0 deletions**. The only
remote-object update saved the rotated Netcup refresh token. Both live repository-only
Observatory inventory entries (p07 and k8s-modules) were preserved. A subsequent
state inspection confirmed no entries remain beneath the old application modules.
The completed move blocks were then removed as requested.

Post-removal validation passed. A follow-up plan with `-refresh=false` found no
remaining moves, creates, replacements or deletions. Its only proposed update was
the Netcup refresh-token secret again: the external token exchange still runs
during planning. That follow-up plan was not applied.

Observatory's three historical `removed` blocks retain their original nested
addresses and `destroy = false`, preserving the existing Helm workload handoff.
Data sources are read again at their new addresses. Backup's JSON retains the
old typed input's null defaults for omitted optional attributes.

Party remains disabled in `party.tf.disabled`; it has no live state to migrate.
Enabling it is a separate deployment decision.

## Using the migrated state

Merge this p07 change before consuming a `k8s-modules` release that removes the
application-specific modules. Existing published tags remain usable. Run
`terraform init` and `terraform validate` in the configured checkout; the usual
generated `backend.tf` supplies root variable declarations.

The committed configuration now requires the migrated p07 state. Do not apply the
old module-based configuration against it. Restoring a pre-migration state snapshot
or migrating another environment requires recreating the corresponding move blocks
before planning; otherwise Terraform would propose resource recreation. Any future
apply still requires explicit operator approval.

Application builds and chart releases remain in their respective repositories.
Future app-specific configuration edits happen here; shared platform/auth/storage
behavior continues to be released through `k8s-modules`.
