# App Azure cleanup for the Switzerland North migration

```bash
bash scripts/destroy_app_azure_resources.sh
```

This is a plan-only wrapper around `scripts/destroy.sh`. It selects the app Key Vaults
and frontend storage accounts present in Terraform state, including Observatory,
and passes their exact resource addresses as `-target` arguments.

The wrapper always passes `--plan-only` to the existing destroy script, which
sets up SSH/provider access and saves a destroy plan as `tfplan` without applying.
The optional `--plan-only` argument is also accepted for compatibility; neither
invocation applies the plan. Terraform includes downstream dependents in the
plan. The master vault, backend/OIDC storage
and `ibari` backup/story storage are not selected as targets. If no app targets
are present, the wrapper exits without invoking the destroy script.

Review the plan to understand the resources and data affected by a potential
migration. Terraform destruction is prohibited by this repository's contributor
instructions; this helper does not authorize or execute it. Keep `tfplan` private
and out of version control because plans can contain secrets.

Migration planning must account for frontend storage contents, required vault
secrets, generated encryption keys/passwords, and resource names in the new
region. Soft-deleted vault names can remain reserved; recovery restores a vault
in its original region. Any infrastructure apply requires separate explicit
operator approval.
