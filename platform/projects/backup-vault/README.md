# backup-vault

AWS Backup vault, its customer managed key and the role AWS Backup runs as in
that account. One project, two instances in a typical setup:

| Instance | Where | Purpose |
|----------|-------|---------|
| `backup-central-vault` | backup platform, dedicated backup account | Destination of every cross-account copy; locked |
| `backup-local-vault` | each workload platform, workload account | Source vault the backup policy writes to first |

AWS Backup always writes to a vault in the resource's own account; the
policy's copy action then ships the recovery point to the central vault.
Restores always run in the source account, so a recovery point that expired
locally is first copied back from the central vault.

## Configuration

Defaults are the **local** (source) profile: `vault_name` and `role_name`
match `backup-policies.source_vault_name` / `iam_role_name`, restores are
enabled, no Vault Lock. The central instance overrides names, restores and
the lock. See `config-central.auto.tfvars.example` and
`config-local.auto.tfvars.example` for both profiles.

The central vault's lock window must contain `backup-policies.copy_retention_days`,
or copy jobs are rejected. Only governance mode is available.

## Cross-account access

`peer_account_id` / `peer_account_ids` and/or `organization_id` (+ optional
`org_paths`) drive two policies:

- vault access policy — `backup:CopyIntoBackupVault` only;
- created key policy — usage actions, and `kms:CreateGrant` only when
  `kms:GrantIsForAWSResource` is true.

The central vault grants the organization (new workload accounts are covered
automatically); a source vault grants only the backup account. The source
key's share is also what lets resources that keep their own encryption (RDS,
Aurora, DocumentDB, EBS) be copied cross-account: encrypt them with this
project's `kms_key_arn` output (e.g. `rds-*.kms_key_id`). Resources on AWS
managed keys cannot be copied cross-account.

## Bringing your own key

With `kms_key_arn` set (for example a key managed centrally by another
project), the key policy is not managed here. It must grant the peers the
permissions listed above.

## Pipeline wiring

```yaml
# platforms/backup/pipeline.yaml
- project: backup-central-vault
  source: propeller:backup-vault
  target: backup-central
  inputs:
    - name: "@landing-zone/workload-parameters.organization_id"
      var: organization_id
  outputs:
    - name: vault_arn
    - name: account_id

# each workload platform
- project: backup-local-vault
  source: propeller:backup-vault
  target: workload-acme-prod
  inputs:
    - name: "@backup/backup-central-vault.account_id"
      var: peer_account_id
  outputs:
    - name: kms_key_arn
```

See the full backup platform in
[`backup-policies`](../backup-policies/README.md#backup-platform).

## References

- [Creating backup copies across AWS accounts](https://docs.aws.amazon.com/aws-backup/latest/devguide/create-cross-account-backup.html)
- [AWS Backup Vault Lock](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html)
- [How encryption works in AWS Backup](https://aws.amazon.com/blogs/storage/how-encryption-works-in-aws-backup/)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vault"></a> [vault](#module\_vault) | ../../../shared/modules/backup-vault | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_enable_restores"></a> [enable\_restores](#input\_enable\_restores) | Attach the AWS managed restore policy to the role. Needed where restores run. | `bool` | `true` | no |
| <a name="input_kms_key_alias"></a> [kms\_key\_alias](#input\_kms\_key\_alias) | Alias (without 'alias/') for the created key. Defaults to backup/<vault\_name>. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Existing CMK (e.g. managed centrally). Null creates one; see README for its key policy. | `string` | `null` | no |
| <a name="input_org_paths"></a> [org\_paths](#input\_org\_paths) | Narrows organization\_id to these aws:PrincipalOrgPaths patterns (e.g. o-xxx/r-xxx/ou-xxx/*). | `list(string)` | `[]` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Grant every principal in this organization, e.g. from workload-parameters.organization\_id. | `string` | `null` | no |
| <a name="input_peer_account_id"></a> [peer\_account\_id](#input\_peer\_account\_id) | Single peer account ID, for pipeline wiring (e.g. the backup account's account\_id). | `string` | `null` | no |
| <a name="input_peer_account_ids"></a> [peer\_account\_ids](#input\_peer\_account\_ids) | Additional peer account IDs. | `list(string)` | `[]` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the vault. Must be one of the regions in the backup policy. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the AWS Backup role. For a source vault, must match backup-policies.iam\_role\_name. | `string` | `"propeller-backup-role"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_vault_lock"></a> [vault\_lock](#input\_vault\_lock) | Governance-mode Vault Lock window; copy retention must fall inside it. Null (default) disables it. | <pre>object({<br/>    min_retention_days = number<br/>    max_retention_days = number<br/>  })</pre> | `null` | no |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the vault. For a source vault, must match backup-policies.source\_vault\_name. | `string` | `"propeller-backup"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | ID of the account hosting the vault. Wire the central instance's value into source vaults. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the vault key. On a source vault, encrypt backed-up resources with it (e.g. rds-*.kms\_key\_id). |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the AWS Backup role. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the vault. The central instance's value feeds backup-policies.copy\_vault\_arn. |
| <a name="output_vault_name"></a> [vault\_name](#output\_vault\_name) | Name of the vault. |
<!-- END_TF_DOCS -->
