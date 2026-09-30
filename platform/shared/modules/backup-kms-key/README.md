# backup-kms-key

Symmetric customer managed key with an alias and a key policy that keeps the
account-root statement AWS requires, plus optional cross-account statements
driven by `cross_account_access`:

- `account_ids` — usage actions for each account root, and `kms:CreateGrant`
  only when `kms:GrantIsForAWSResource` is true;
- `organization_id` (optionally narrowed by `org_paths`) — the same two
  statements for any principal in the organization.

Key for AWS Backup vaults, and for the resources whose recovery points are
copied across accounts (RDS, Aurora, DocumentDB, EBS keep their own key in
backups). Used by `backup-vault`; also the starting point for a project that
manages backup keys centrally.

## References

- [Allowing users in other accounts to use a KMS key](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html)
- [Encryption for backups in AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html)

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
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alias"></a> [alias](#input\_alias) | Alias name for the key, without the 'alias/' prefix. | `string` | n/a | yes |
| <a name="input_cross_account_access"></a> [cross\_account\_access](#input\_cross\_account\_access) | Principals outside this account allowed to use the key: explicit account IDs,<br/>and/or every principal in organization\_id, optionally narrowed to org\_paths.<br/>See README for the generated statements. | <pre>object({<br/>    account_ids     = optional(list(string), [])<br/>    organization_id = optional(string)<br/>    org_paths       = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_deletion_window_in_days"></a> [deletion\_window\_in\_days](#input\_deletion\_window\_in\_days) | Waiting period before the key is deleted after a destroy (7-30). | `number` | `30` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the customer managed key. | `string` | n/a | yes |
| <a name="input_enable_rotation"></a> [enable\_rotation](#input\_enable\_rotation) | Enable automatic yearly key rotation. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the key alias. |
| <a name="output_key_arn"></a> [key\_arn](#output\_key\_arn) | ARN of the customer managed key. |
| <a name="output_key_id"></a> [key\_id](#output\_key\_id) | ID of the customer managed key. |
<!-- END_TF_DOCS -->
