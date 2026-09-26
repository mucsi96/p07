# p07 - Contributor guidance

## Code Review Rules

- Review the PR diff for actionable correctness, security, data-loss, and deployment regressions; cite the changed file/line and concrete impact.
- Preserve authentication boundaries, persisted data compatibility, and the project's documented build/test/deploy contracts. Adapt shared patterns to this project's stack.
- Report missing behavioral coverage where it would catch a specific regression; leave formatting and mechanical checks to CI.

## Codex automation

Use native Codex GitHub reviews and `@codex` PR tasks with ChatGPT sign-in.
Setup: https://github.com/mucsi96/skeleton-app/blob/main/docs/codex-automation.md
Fleet inventory and activation: `docs/codex-migration.md`.
Terraform updates: `.github/prompts/update-terraform-versions.md`.

## Infrastructure

Read README.md for the provisioning and application ownership boundaries.
Keep published module references explicit. Check changes for resource replacement,
database/storage loss, workload identity, and permissions across application namespaces.
Automation may propose changes; it must not run Terraform apply/destroy or reinstall
the server. Never include state, plan files, kubeconfigs, or credentials in a PR.
