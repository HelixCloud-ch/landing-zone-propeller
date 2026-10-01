# kms-keys

Customer managed KMS keys for the account the step targets, one per entry
of `keys`. Deploy one instance per account that needs keys, before the
projects that encrypt with them (RDS, Aurora, DocumentDB, ...).

## How a key is built

Each entry produces a policy document (`backup-kms-key-policy`) and a key
with an alias (`kms-key`). The policy is computed separately from the key,
so a later change of access profile updates the policy in place instead of
replacing the key. Destroying a key schedules its deletion; data encrypted
with it becomes unrecoverable after the window.

`shared_with` lists account names, resolved against the two landing-zone
account maps after the same normalization as `workload-account-registry`
(lowercase, spaces as hyphens), so the names match pipeline targets. Each
resolved account gets key usage, and `kms:CreateGrant` only for AWS services
acting on its behalf. That is what AWS Backup needs to copy RDS, Aurora,
DocumentDB and EBS recovery points into the backup account, since those
keep the source key.

## Field reference

| Field | Default | Notes |
|-------|---------|-------|
| `alias` | `propeller/<name>` | Without `alias/`; must not start with `aws/`; unique |
| `description` | generated | |
| `shared_with` | `[]` | Names from `workload_account_ids` / `landing_zone_account_ids` |
| `account_ids` | `[]` | Raw 12-digit IDs outside those maps |
| `share_with_organization` | `false` | Any principal in `organization_id` |
| `org_paths` | `[]` | Narrows the organization statement; requires `share_with_organization` |
| `enable_rotation` | `true` | `false` for imported material or custom key stores |
| `rotation_period_in_days` | AWS default (365) | 90-2560 |
| `deletion_window_in_days` | `30` | 7-30 |

See `config.auto.tfvars.example`, including a key with
`enable_rotation = false`.

## Pipeline wiring

```yaml
- project: kms-keys
  source: propeller:kms-keys
  target: workload-acme-prod
  inputs:
    - name: "@landing-zone/workload-parameters.account_ids"
      var: workload_account_ids
    - name: "@landing-zone/accounts.account_ids"
      var: landing_zone_account_ids
    - name: "@landing-zone/workload-parameters.organization_id"
      var: organization_id
  outputs:
    - name: key_arns
```

`key_arns` is a name → ARN map. A project that takes a single key (e.g.
`kms_key_id` on `rds-postgresql`) picks one entry with an input `expr`
([Input Transforms](../../../docs/input-transforms.md)):

```yaml
- project: rds-app
  source: propeller:rds-postgresql
  target: workload-acme-prod
  inputs:
    - name: kms-keys.key_arns
      var: kms_key_id
      expr: '$exists($lookup($, "rds")) ? $lookup($, "rds") : $error("kms-keys has no key rds")'
```

Use `$lookup` rather than a bare path so names with hyphens work. Keep the
`$error` guard: a plain `$lookup` on a missing name returns undefined, and
the step would receive an empty or invalid value instead of failing.

## Operational notes

- RDS, Aurora and DocumentDB cannot change their storage key in place; only
  new or restored instances pick up a key from here.
- Removing an entry schedules the key for deletion after
  `deletion_window_in_days`. Cancel with `aws kms cancel-key-deletion` if
  it was a mistake.

## What does NOT belong here

- The key of a backup vault created by `backup-vault` itself (it creates
  its own unless given `kms_key_arn`).
- Access profiles other than cross-account service use (specific roles,
  `kms:ViaService`, service principals, separated key administrators):
  those need their own policy module.

## References

- [Allowing users in other accounts to use a KMS key](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html)
- [Encryption for backups in AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html)
- [EnableKeyRotation](https://docs.aws.amazon.com/kms/latest/APIReference/API_EnableKeyRotation.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_keys"></a> [keys](#module\_keys) | ../../../shared/modules/kms-key | n/a |
| <a name="module_policy"></a> [policy](#module\_policy) | ../../../shared/modules/backup-kms-key-policy | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_keys"></a> [keys](#input\_keys) | Keys to create, keyed by name (output map key). alias defaults to<br/>propeller/<name>; shared\_with lists account names (target names) from the<br/>landing-zone maps. See README for the field reference. | <pre>map(object({<br/>    description             = optional(string)<br/>    alias                   = optional(string)<br/>    shared_with             = optional(list(string), [])<br/>    account_ids             = optional(list(string), [])<br/>    share_with_organization = optional(bool, false)<br/>    org_paths               = optional(list(string), [])<br/>    enable_rotation         = optional(bool, true)<br/>    rotation_period_in_days = optional(number)<br/>    deletion_window_in_days = optional(number, 30)<br/>  }))</pre> | n/a | yes |
| <a name="input_landing_zone_account_ids"></a> [landing\_zone\_account\_ids](#input\_landing\_zone\_account\_ids) | Account name to ID, from @landing-zone/accounts.account\_ids. Resolves shared\_with. | `map(string)` | `{}` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Organization ID, from @landing-zone/workload-parameters.organization\_id. Needed for share\_with\_organization. | `string` | `null` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the keys. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_workload_account_ids"></a> [workload\_account\_ids](#input\_workload\_account\_ids) | Account name to ID, from @landing-zone/workload-parameters.account\_ids. Resolves shared\_with. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arns"></a> [alias\_arns](#output\_alias\_arns) | Map of key name to alias ARN. |
| <a name="output_key_arns"></a> [key\_arns](#output\_key\_arns) | Map of key name to key ARN. |
| <a name="output_key_ids"></a> [key\_ids](#output\_key\_ids) | Map of key name to key ID. |
<!-- END_TF_DOCS -->
