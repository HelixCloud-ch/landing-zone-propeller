# backup-kms-key-policy

Key policy document (no resources) for keys used by AWS Backup and by the
resources whose recovery points are copied across accounts (RDS, Aurora,
DocumentDB, EBS keep their own key in backups). Feed `json` to `kms-key`.

Statements:

- account root `kms:*` — the statement AWS requires so the key stays
  manageable through IAM;
- `cross_account_access.account_ids` — usage actions for each account root,
  and `kms:CreateGrant` only when `kms:GrantIsForAWSResource` is true;
- `cross_account_access.organization_id` (optionally narrowed by
  `org_paths`) — the same two statements for any principal in the
  organization.

## Scope

The profile trusts whole accounts (or the organization) and lets an AWS
service act on their behalf. It does not fit when access must be limited
to a specific role, to specific services (`kms:ViaService`), to a service
principal (CloudWatch Logs, SNS, CloudTrail), or when key administrators
must be separated from key users. Those are separate policy modules next to
this one, feeding the same `kms-key`.

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
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cross_account_access"></a> [cross\_account\_access](#input\_cross\_account\_access) | Principals outside this account allowed to use the key: explicit account IDs,<br/>and/or every principal in organization\_id, optionally narrowed to org\_paths.<br/>See README for the generated statements. | <pre>object({<br/>    account_ids     = optional(list(string), [])<br/>    organization_id = optional(string)<br/>    org_paths       = optional(list(string), [])<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_json"></a> [json](#output\_json) | Key policy document (JSON), for kms-key's policy\_json. |
<!-- END_TF_DOCS -->
