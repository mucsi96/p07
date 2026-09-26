# Update Terraform versions

Run weekly on Wednesday at 08:00 UTC in a ChatGPT/Codex scheduled task for
`mucsi96/p07`. This file defines the task; it does not enable a schedule.

Read `AGENTS.md`. Work from the latest default branch in an isolated worktree
or cloud checkout. Check for an existing open version-update PR first and
update it instead of opening duplicates.

1. Read `main.tf` and identify pinned versions with an inline source URL comment.
   That URL is the source of truth for the component's release feed.
2. Fetch the latest stable, non-draft, non-prerelease version using GitHub release
   APIs or `gh release list` / `gh release view`. Respect component-specific tag
   filters in URLs such as `releases?q=...`; do not substitute a different chart
   from the same repository. Report lookup failures instead of guessing versions.
3. Preserve prefix style (`v` or bare semver), formatting, alignment, and comments.
   Extract the relevant semver from component-prefixed tags when necessary.
4. Only edit `main.tf`. Only update pinned versions with inline source URLs;
   leave constraints such as `>=` intact. Do not change module refs without the
   required inline source comment.
5. If no update is needed, report a no-op. Otherwise validate the diff and run
   available formatting/validation checks. Report checks that cannot run. Do not
   apply Terraform, destroy resources, reinstall the server, or deploy anything.
6. Commit the scoped changes on a `codex/update-terraform-versions-<date>` branch
   and open/update a PR against the default branch titled
   `chore: update Terraform versions to latest`. List each `<key>: <old> -> <new>`
   with its source URL and validation outcome. Return the PR URL; do not merge.
