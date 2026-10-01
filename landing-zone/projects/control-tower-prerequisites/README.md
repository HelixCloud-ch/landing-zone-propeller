# Control Tower Prerequisites

Creates the prerequisite resources required before enabling AWS Control Tower
via the `CreateLandingZone` API (or `aws_controltower_landing_zone` Terraform
resource).

## What it creates

All resources are optional except the Security OU.

| Resource | Controlled by | Default |
|---|---|---|
| Security OU | always created | — |
| Log Archive account | `LOG_ARCHIVE_EMAIL` set | skipped |
| Security Tooling account | `AUDIT_EMAIL` set | skipped |
| Backup Admin account | `BACKUP_ADMIN_EMAIL` + `BACKUP_CENTRAL_EMAIL` both set | skipped |
| Central Backup account | `BACKUP_ADMIN_EMAIL` + `BACKUP_CENTRAL_EMAIL` both set | skipped |
| 4 CT IAM service roles | `CREATE_IAM_ROLES=true` | created |

The 4 IAM service roles are:
- `AWSControlTowerAdmin` — inline policy + `AWSControlTowerServiceRolePolicy`
- `AWSControlTowerCloudTrailRole` — `AWSControlTowerCloudTrailRolePolicy`
- `AWSControlTowerStackSetRole` — inline policy (AssumeRole → AWSControlTowerExecution)
- `AWSControlTowerConfigAggregatorRoleForOrganizations` — `AWSConfigRoleForOrganizations`

## Account naming rationale

### "Security Tooling" instead of "Audit"

CT names this account "Audit" by default, but the AWS SRA and the AWS
multi-account strategy whitepaper call it **"Security Tooling (Audit)"**,
noting that "Audit" is just the CT default name.

The account is the delegated administrator for Security Hub, GuardDuty,
Config, Macie, IAM Access Analyzer, Firewall Manager, Detective, Audit
Manager, Inspector, and CloudTrail — it is a security operations hub, not
merely an audit account. "Security Tooling" better reflects this role.

References:
- [AWS SRA — Security Tooling account](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/security-tooling.html):
  "AWS Control Tower names the account under the Security OU the *Audit Account* by default. You can rename the account during the AWS Control Tower setup."
- [Organizing Your AWS Environment — Foundational OUs](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/foundational-ous.html):
  Uses "Security Tooling (Audit)" throughout, explicitly noting CT's default is "Audit".
- [CT configure shared accounts](https://docs.aws.amazon.com/controltower/latest/userguide/configure-shared-accounts.html):
  "Many customers choose to call [the audit account] the **Security** account."

CT identifies accounts by account ID in the manifest, not by name — the
name is purely organizational.

### "Log Archive"

Consistent across CT console defaults, AWS SRA, and the multi-account
whitepaper. No change needed.

## Backup accounts

The backup accounts are required only if you plan to enable the AWS Backup
integration in the CT v3.3 manifest (`backup.enabled: true`). They map to
`backup.configurations.backupAdmin.accountId` and
`backup.configurations.centralBackup.accountId` in the manifest.

### What each account does

**Backup Administrator account** — the control plane for backup operations.
It is the delegated administrator for AWS Backup across the org. It stores
Backup Audit Manager (BAM) report plans and aggregates all monitoring data
(restore jobs, copy jobs) in an S3 bucket.

**Central Backup account** — the data plane. It stores the actual backup
vaults and cross-account backup copies. Keeping backups here means that if
a workload account is compromised, the backup data is safe in a separate
account.

### Can you use the same account for both?

The CT prerequisites docs say "two other AWS accounts" and the AWS blog
post says "two specialized accounts" — the separation is intentional and
a security best practice. The CT v3.3 schema has two distinct `accountId`
fields. Technically you can pass the same account ID for both, but it
defeats the purpose: the separation ensures that a compromise of one
account does not affect the other.

For small or non-production setups, using a single account is possible.
For production, use two separate accounts.

References:
- [CT backup prerequisites](https://docs.aws.amazon.com/controltower/latest/userguide/backup-prerequisites.html)
- [Build centralized cross-Region backup architecture with CT](https://aws.amazon.com/blogs/storage/build-centralized-cross-region-backup-architecture-with-aws-control-tower/)

## Required inputs

| Variable | Default | Description |
|---|---|---|
| `LOG_ARCHIVE_EMAIL` | *(empty)* | Root email for the Log Archive account (optional) |
| `AUDIT_EMAIL` | *(empty)* | Root email for the Security Tooling account (optional) |
| `BACKUP_ADMIN_EMAIL` | *(empty)* | Root email for the Backup Admin account (optional) |
| `BACKUP_CENTRAL_EMAIL` | *(empty)* | Root email for the Central Backup account (optional) |
| `CREATE_IAM_ROLES` | `true` | Set to `false` to skip IAM role creation (e.g. roles already exist) |
| `ACTION` | `plan` | `plan` or `apply` |

Each account is created only when its email is provided. Backup accounts
require **both** emails to be set — if either is empty, both are skipped.

Set `CREATE_IAM_ROLES=false` when:
- A previous CT installation already created the roles
- You are re-running this project after a partial failure where roles were created
- The customer already has an existing CT setup and only needs the accounts

## Skipping for existing environments

If a customer already has the Security OU and the required accounts, skip
this project entirely.

## Notes

- Accounts have `prevent_destroy = true` — Terraform will refuse to destroy them
- `close_on_deletion = false` — removing from state only detaches, does not close
- IAM role names are fixed by AWS (not configurable)
- All roles use the `/service-role/` IAM path as required by CT

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.41 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.control_tower_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.control_tower_cloudtrail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.control_tower_config_aggregator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.control_tower_stackset](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.control_tower_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.control_tower_stackset](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.control_tower_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.control_tower_cloudtrail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.control_tower_config_aggregator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_organizations_account.audit](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |
| [aws_organizations_account.backup_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |
| [aws_organizations_account.backup_central](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |
| [aws_organizations_account.log_archive](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |
| [aws_organizations_organizational_unit.security](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_audit_account_email"></a> [audit\_account\_email](#input\_audit\_account\_email) | Root email address for the Security Tooling (Audit) account. Leave empty to skip creation. | `string` | `""` | no |
| <a name="input_audit_account_name"></a> [audit\_account\_name](#input\_audit\_account\_name) | Friendly name for the Security Tooling (Audit) account. | `string` | `"Security Tooling"` | no |
| <a name="input_backup_admin_account_email"></a> [backup\_admin\_account\_email](#input\_backup\_admin\_account\_email) | Root email address for the Backup Administrator account. Leave empty to skip creation. | `string` | `""` | no |
| <a name="input_backup_admin_account_name"></a> [backup\_admin\_account\_name](#input\_backup\_admin\_account\_name) | Friendly name for the Backup Administrator account. | `string` | `"Backup Admin"` | no |
| <a name="input_backup_central_account_email"></a> [backup\_central\_account\_email](#input\_backup\_central\_account\_email) | Root email address for the Central Backup account. Leave empty to skip creation. | `string` | `""` | no |
| <a name="input_backup_central_account_name"></a> [backup\_central\_account\_name](#input\_backup\_central\_account\_name) | Friendly name for the Central Backup account. | `string` | `"Central Backup"` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_create_iam_roles"></a> [create\_iam\_roles](#input\_create\_iam\_roles) | Whether to create the four CT IAM service roles. Set to false if the roles already exist (e.g. a previous CT installation). | `bool` | `true` | no |
| <a name="input_log_archive_account_email"></a> [log\_archive\_account\_email](#input\_log\_archive\_account\_email) | Root email address for the Log Archive account. Leave empty to skip creation. | `string` | `""` | no |
| <a name="input_log_archive_account_name"></a> [log\_archive\_account\_name](#input\_log\_archive\_account\_name) | Friendly name for the Log Archive account. | `string` | `"Log Archive"` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where Control Tower will be deployed. | `string` | n/a | yes |
| <a name="input_security_ou_name"></a> [security\_ou\_name](#input\_security\_ou\_name) | Name of the Security OU that will contain the service integration accounts. | `string` | `"Security"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_audit_account_id"></a> [audit\_account\_id](#output\_audit\_account\_id) | AWS account ID of the Security Tooling (Audit) account (empty if not created). |
| <a name="output_backup_admin_account_id"></a> [backup\_admin\_account\_id](#output\_backup\_admin\_account\_id) | AWS account ID of the Backup Administrator account (empty if not created). |
| <a name="output_backup_central_account_id"></a> [backup\_central\_account\_id](#output\_backup\_central\_account\_id) | AWS account ID of the Central Backup account (empty if not created). |
| <a name="output_control_tower_admin_role_arn"></a> [control\_tower\_admin\_role\_arn](#output\_control\_tower\_admin\_role\_arn) | ARN of the AWSControlTowerAdmin IAM role (empty if not created). |
| <a name="output_control_tower_cloudtrail_role_arn"></a> [control\_tower\_cloudtrail\_role\_arn](#output\_control\_tower\_cloudtrail\_role\_arn) | ARN of the AWSControlTowerCloudTrailRole IAM role (empty if not created). |
| <a name="output_control_tower_config_aggregator_role_arn"></a> [control\_tower\_config\_aggregator\_role\_arn](#output\_control\_tower\_config\_aggregator\_role\_arn) | ARN of the AWSControlTowerConfigAggregatorRoleForOrganizations IAM role (empty if not created). |
| <a name="output_control_tower_stackset_role_arn"></a> [control\_tower\_stackset\_role\_arn](#output\_control\_tower\_stackset\_role\_arn) | ARN of the AWSControlTowerStackSetRole IAM role (empty if not created). |
| <a name="output_log_archive_account_id"></a> [log\_archive\_account\_id](#output\_log\_archive\_account\_id) | AWS account ID of the Log Archive account (empty if not created). |
| <a name="output_security_ou_id"></a> [security\_ou\_id](#output\_security\_ou\_id) | ID of the Security OU. |
<!-- END_TF_DOCS -->