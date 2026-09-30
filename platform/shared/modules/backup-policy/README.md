# backup-policy

Organizations `BACKUP_POLICY` with one plan, one rule and one tag selection,
attached to every ID in `target_ids`.

- Every leaf is wrapped in `@@assign`; numbers are sent as strings.
- The selection role ARN uses the literal `$account` placeholder, which
  Organizations resolves per receiving account.
- An optional copy action to `copy_vault_arn` carries its own lifecycle, so
  the short source retention does not propagate to the copy.
- Cold storage is intentionally not exposed yet.

Requires the `BACKUP_POLICY` type to be enabled on the root
(`backup-org-settings`).

## References

- [Backup policy syntax and examples](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup_syntax.html)

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
| [aws_organizations_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_completion_window_minutes"></a> [completion\_window\_minutes](#input\_completion\_window\_minutes) | Minutes within which the job must complete. Null keeps the AWS default. | `number` | `null` | no |
| <a name="input_copy_retention_days"></a> [copy\_retention\_days](#input\_copy\_retention\_days) | Retention of the copied recovery points. Required when copy\_vault\_arn is set. | `number` | `null` | no |
| <a name="input_copy_vault_arn"></a> [copy\_vault\_arn](#input\_copy\_vault\_arn) | Vault ARN (usually central) every recovery point is copied to. Null disables the copy. | `string` | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the Organizations backup policy. | `string` | `"AWS Backup policy managed by propeller."` | no |
| <a name="input_iam_role_name"></a> [iam\_role\_name](#input\_iam\_role\_name) | Name of the AWS Backup role that must exist in every member account the policy reaches. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the Organizations backup policy. Also the plan name unless plan\_name is set. | `string` | n/a | yes |
| <a name="input_plan_name"></a> [plan\_name](#input\_plan\_name) | Backup plan name inside the policy. Defaults to name. | `string` | `null` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Regions the backup plan applies to. | `list(string)` | n/a | yes |
| <a name="input_rule_name"></a> [rule\_name](#input\_rule\_name) | Name of the backup rule and of its tag selection. | `string` | `"default"` | no |
| <a name="input_schedule_expression"></a> [schedule\_expression](#input\_schedule\_expression) | Schedule of the backup rule, e.g. cron(0 2 ? * * *). | `string` | n/a | yes |
| <a name="input_selection_tag_key"></a> [selection\_tag\_key](#input\_selection\_tag\_key) | Tag key that selects resources for backup. | `string` | `"backup"` | no |
| <a name="input_selection_tag_values"></a> [selection\_tag\_values](#input\_selection\_tag\_values) | Tag values (any of) that select resources for backup. | `list(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_source_retention_days"></a> [source\_retention\_days](#input\_source\_retention\_days) | Source-vault retention. Kept short when a copy action holds the real retention. | `number` | `1` | no |
| <a name="input_source_vault_name"></a> [source\_vault\_name](#input\_source\_vault\_name) | Name of the vault receiving recovery points in each member account. Must exist in every target. | `string` | n/a | yes |
| <a name="input_start_window_minutes"></a> [start\_window\_minutes](#input\_start\_window\_minutes) | Minutes after the schedule within which the job must start. Null keeps the AWS default. | `number` | `null` | no |
| <a name="input_target_ids"></a> [target\_ids](#input\_target\_ids) | Root, OU or account IDs the policy is attached to. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_arn"></a> [policy\_arn](#output\_policy\_arn) | ARN of the Organizations backup policy. |
| <a name="output_policy_content"></a> [policy\_content](#output\_policy\_content) | Rendered policy document (JSON), for review. |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | ID of the Organizations backup policy. |
<!-- END_TF_DOCS -->
