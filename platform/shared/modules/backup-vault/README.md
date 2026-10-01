# backup-vault

AWS Backup vault with:

- a customer managed key, created through `kms-key` with the
  `backup-kms-key-policy` profile unless
  `kms_key_arn` is supplied (a supplied key's policy is the caller's responsibility);
- an optional vault access policy granting only `backup:CopyIntoBackupVault`
  to `cross_account_access` (accounts and/or organization + org paths);
- an optional **governance-mode** Vault Lock. `changeable_for_days` is never
  set, so the module cannot create an irreversible compliance-mode lock;
- the IAM role AWS Backup assumes in this account, with
  `AWSBackupServiceRolePolicyForBackup` (includes the identity-based copy
  permissions) and, when `enable_restores`, the restore policy. An
  Organizations backup policy references this role by name in every member
  account.

Used by the `backup-vault` project for both the central (destination) and the
source vaults.

## References

- [Creating backup copies across AWS accounts](https://docs.aws.amazon.com/aws-backup/latest/devguide/create-cross-account-backup.html)
- [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html)

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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_kms_key"></a> [kms\_key](#module\_kms\_key) | ../kms-key | n/a |
| <a name="module_kms_key_policy"></a> [kms\_key\_policy](#module\_kms\_key\_policy) | ../backup-kms-key-policy | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_backup_vault.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault_lock_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_lock_configuration) | resource |
| [aws_backup_vault_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.restores](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cross_account_access"></a> [cross\_account\_access](#input\_cross\_account\_access) | Principals allowed to copy into this vault, and to use the created key:<br/>account IDs and/or an organization, optionally narrowed to org\_paths.<br/>Empty (default) creates no vault access policy. | <pre>object({<br/>    account_ids     = optional(list(string), [])<br/>    organization_id = optional(string)<br/>    org_paths       = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_enable_restores"></a> [enable\_restores](#input\_enable\_restores) | Also attach AWSBackupServiceRolePolicyForRestores to the role. | `bool` | `true` | no |
| <a name="input_kms_key_alias"></a> [kms\_key\_alias](#input\_kms\_key\_alias) | Alias (no 'alias/' prefix) for the created key. Defaults to backup/<name>; ignored with kms\_key\_arn. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of an existing customer managed key. Null (default) creates a dedicated key for the vault. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the backup vault. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IAM role AWS Backup assumes for backup, copy and restore jobs in this account. | `string` | n/a | yes |
| <a name="input_vault_lock"></a> [vault\_lock](#input\_vault\_lock) | Governance-mode Vault Lock retention window. Null (default) leaves the vault unlocked. | <pre>object({<br/>    min_retention_days = number<br/>    max_retention_days = number<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the key encrypting the vault (created or supplied). |
| <a name="output_kms_key_created"></a> [kms\_key\_created](#output\_kms\_key\_created) | True when the module created the key, false when kms\_key\_arn was supplied. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the AWS Backup role. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the AWS Backup role. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the backup vault. |
| <a name="output_vault_name"></a> [vault\_name](#output\_vault\_name) | Name of the backup vault. |
<!-- END_TF_DOCS -->
