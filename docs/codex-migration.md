# Codex migration inventory

## Scope

Inventory taken from local checkouts, p07 `main.tf`/`dashboard.tf`, and GitHub
repository secret names on 2026-09-26. All repositories below belong to
`mucsi96` on GitHub. The selected authentication is **ChatGPT subscription**.

| Repository | p07 role | Native review guidance | Skeleton sync task |
| --- | --- | --- | --- |
| skeleton-app | Hello app / reference | Prepared | Source; no self-sync |
| learn-language | Language app | Prepared | Prepared |
| training-log-pro | Training app | Prepared | Prepared |
| expense-tracker | Expense app | Prepared | Prepared |
| library-app | Library app | Prepared | Prepared |
| cooking-app | Cooking app | Prepared | Prepared; newly added |
| postgres-azure-backup | Backup app | Prepared | Prepared |
| observatory-app | Fleet dashboard | Prepared; newly added | Prepared; newly added |
| p07 | Environment provisioning | Prepared | Not a downstream app |
| k8s-modules | Shared infrastructure | Prepared | Not a downstream app |
| k8s-helm-charts | Shared charts | Prepared | Not a downstream app |
| image-processor | Other checkout with Claude review | Prepared | Not a p07 app |
| film-tracker | Other checkout with untracked Claude workflows | Prepared | Not a p07 app |

`learn-language-old` is an older checkout of the same remote, with local work
and no Claude automation; the current `learn-language` checkout is the migration
target. Other checked-out repositories had no Claude code-review integration.

## Repository changes

- Removed 12 Claude review and 12 Claude mention/issue workflows, including the
  two untracked workflow files in film-tracker.
- Replaced five Claude skeleton-sync workflows with seven consistent scheduled
  task prompts, including Cooking and Observatory.
- Replaced p07's Claude Terraform updater with a scheduled task prompt.
- Added matching root `AGENTS.md` review rules in all 13 repositories. Existing
  project guidance is retained; image-processor's guide moved from `CLAUDE.md`.
- Shared subscription-only setup and synchronization procedure live in
  [skeleton-app/docs/codex-automation.md](https://github.com/mucsi96/skeleton-app/blob/main/docs/codex-automation.md).

This aligns the **automation setup**. It does not claim that every application's
implementation already matches the latest skeleton revision. The first sync task
must audit relevant patterns and establish its checkpoint through a reviewed PR.

## Activation status

The owner confirmed that the GitHub connector has access to all repositories
and that native automatic reviews are enabled. Migration changes are being
submitted as repository PRs. Scheduled tasks and obsolete-secret cleanup remain
pending. Account-side settings are owner-confirmed, not independently verified
with the GitHub CLI session.

- [ ] Publish the repository changes, including the shared skeleton guidance.
- [x] Connect GitHub to Codex cloud and grant access to all 13 repositories.
- [x] Enable Code review and Automatic reviews consistently for all 13 at
  <https://chatgpt.com/codex/settings/code-review>.
- [ ] Verify a manual `@codex review` and an automatic review per repository;
  record representative PR URLs here.
- [ ] Create seven skeleton-sync tasks, Tuesday 06:00 UTC, following the shared
  guide and each target's `.github/prompts/sync-skeleton.md`.
- [ ] Create the p07 Terraform-update task, Wednesday 08:00 UTC, with the prompt:

  ```text
  In mucsi96/p07, follow .github/prompts/update-terraform-versions.md from the
  current default branch. Propose applicable version updates in a pull request,
  report validation results and its URL, and do not merge or apply infrastructure.
  ```

- [ ] Run each scheduled task manually, verify repository write/PR capabilities,
  and record task names/links and first-run outcomes here.
- [ ] Remove obsolete required Claude checks, retaining build/test requirements.
- [ ] After verifying replacement automation, delete obsolete
  `CLAUDE_CODE_OAUTH_TOKEN` secrets from expense-tracker, k8s-helm-charts,
  k8s-modules, learn-language, p07, postgres-azure-backup, skeleton-app, and
  training-log-pro; remove unused Claude GitHub app access.

No `OPENAI_API_KEY` or Codex auth-cache secret is needed. Reviews and tasks use
the plan's Codex allowances. The installed GitLab plugin does not enable this
GitHub integration. Prompt files alone do not activate scheduled tasks.

## Local validation

- `git diff --check` passed across all 13 affected repositories.
- All 13 root review-rule sections match; all seven sync task prompts match.
- Scanned 40 remaining GitHub YAML/JSON/shell configuration files across local
  Git checkouts, including untracked files: no Claude action, OAuth-token, or
  mention-trigger integration remains.
- Existing contributor guidance was preserved, including image-processor's
  renamed guide. Application builds were not run for these documentation and
  workflow-removal changes. Native reviews await a representative verified run;
  scheduled tasks await activation.
