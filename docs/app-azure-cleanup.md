# App Azure cleanup for the Switzerland North migration

```bash
bash scripts/destroy_app_azure_resources.sh --plan-only
# Apply by generating a fresh plan and executing it:
bash scripts/destroy_app_azure_resources.sh
```

This is a wrapper around `scripts/destroy.sh`. It selects the app Key Vaults
and frontend storage accounts present in Terraform state, including Observatory,
and passes their exact resource addresses as `-target` arguments.

The existing destroy script sets up SSH/provider access, creates a Terraform
destroy plan and **automatically applies it**. With `--plan-only`, it saves `tfplan`
without applying. Terraform includes downstream dependents and updates state
normally on apply. The master vault, backend/OIDC storage
and `ibari` backup/story storage are not selected as targets. If no app targets
are present, the wrapper exits without invoking the destroy script.

Stop application writes and deployment/maintenance automation and preserve
required data/secrets and a protected Terraform state snapshot before running.
Frontend storage contents are deleted. Vault deletion/purge follows AzureRM
provider settings and Azure purge protection.

Before recreating resources, prepare the new region and names. Soft-deleted vault
names can remain reserved; recovery restores a vault in its original region.
Review the recreation plan, preserve generated encryption keys/passwords and
republish frontend artifacts before restarting applications.
