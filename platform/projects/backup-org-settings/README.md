# backup-org-settings

Runs in the **management account**, as part of a dedicated backup platform
(see [`backup-policies`](../backup-policies/README.md#backup-platform)).
Organization-level prerequisites for
[AWS Backup policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup.html)
managed outside Control Tower's built-in backup integration.

A `just` project calling the AWS CLI, with no Terraform state. None of these
settings has a clean Terraform resource: the policy type is only reachable by
adopting `aws_organizations_organization` (authoritative over every policy
type and trusted-access principal in an org Control Tower also manages), and
the Region's resource-type list has no data source. Every step is idempotent
and runs on each apply, so manual drift is corrected on the next deploy.

## What `apply` does

1. **`BACKUP_POLICY` policy type on the root.** Checks `list-roots` first
   (`enable-policy-type` fails on an already-enabled type), then waits until
   the status is `ENABLED` so `backup-policies` can create policies right
   after. Bounded by `policy_type_timeout_seconds`.
2. **Global settings.** Sets `isCrossAccountBackupEnabled`, and
   `isMpaEnabled` / `isDelegatedAdministratorEnabled` only when given; empty
   leaves them untouched.
3. **Resource-type opt-in.** Plans created by Organizations backup policies
   inherit the **management account's** opt-in, not the member account's
   ([re:Post](https://repost.aws/knowledge-center/backup-policy-no-jobs-created)).
   Every type the Region reports is opted in, then `opt_in_overrides` applies.

Each step only writes when the current value differs. `plan` prints the
current and desired values without changing anything. `destroy` is a no-op:
disabling the policy type would detach every backup policy in the
organization.

## Inputs

Pipeline `literal` inputs (all optional):

| Input | Default | Meaning |
|-------|---------|---------|
| `enable_backup_policy_type` | `true` | Enable `BACKUP_POLICY` on the root |
| `cross_account_backup` | `true` | `isCrossAccountBackupEnabled` |
| `multi_party_approval` | empty (unchanged) | `isMpaEnabled` |
| `delegated_administrator` | empty (unchanged) | `isDelegatedAdministratorEnabled` |
| `opt_in_overrides` | `{}` | JSON object of booleans, e.g. `{"S3":false}` |
| `policy_type_timeout_seconds` | `300` | Max wait for `ENABLED` |

```yaml
- project: backup-org-settings
  source: propeller:backup-org-settings
  target: management
  inputs:
    - var: opt_in_overrides
      literal: '{"S3":false}'
```

## Outputs

`root_id`, `backup_policy_type_status`, `resource_type_opt_in_preference`.

## Operational notes

- Trusted access for `backup.amazonaws.com` is **not** handled here. Add it to
  the landing zone's `org-trusted-access.trusted_service_principals` and
  deploy the landing zone first: `EnablePolicyType` fails with
  `SERVICE_ACCESS_NOT_ENABLED` otherwise
  ([EnablePolicyType errors](https://docs.aws.amazon.com/organizations/latest/APIReference/API_EnablePolicyType.html#API_EnablePolicyType_Errors)).
- Do not combine with Control Tower's backup integration
  (`control-tower.enable_backup`): both manage the same org-level settings.
- The runner needs the AWS CLI, `bash` and `jq` (all in the deploy-runner image).

## What does NOT belong here

- Backup policies themselves — `backup-policies`.
- Vaults, keys and roles — `backup-vault`.
- Delegated administration of AWS Backup — policies stay in the management
  account.

## References

- [Managing AWS Backup resources across multiple AWS accounts](https://docs.aws.amazon.com/aws-backup/latest/devguide/manage-cross-account.html)
- [UpdateGlobalSettings](https://docs.aws.amazon.com/aws-backup/latest/devguide/API_UpdateGlobalSettings.html)
- [EnablePolicyType](https://docs.aws.amazon.com/organizations/latest/APIReference/API_EnablePolicyType.html)
