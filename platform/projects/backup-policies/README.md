# backup-policies

Organizations backup policies, created and attached from the **management
account**: one per entry of `policies`, keyed by policy name. Thin wrapper
around the `backup-policy` module (`for_each`); the only project-side logic is
resolving `target_ou_paths` against the landing zone's OU map
(`workload-parameters.ou_ids`) and defaulting each policy's copy vault to the
pipeline-wired `copy_vault_arn`.

## How a backup flows

1. Each policy reaches every account under its target OUs.
2. Resources tagged `backup=default` (`selection_tag_key` /
   `selection_tag_values`) are backed up on `schedule_expression` into the
   local vault `source_vault_name`, running as `iam_role_name`.
3. Each recovery point is copied to `copy_vault_arn` and kept for
   `copy_retention_days`; the local copy expires after
   `source_retention_days`.

The vault and role must already exist in every member account — deploy
a `backup-vault` instance with matching names (its defaults). Organizations does not create
them, and jobs start but fail without them.

## Retention trade-off

`source_retention_days` defaults to 1 for cost. Copy jobs have no completion
SLA, so a failed copy whose source expires loses that recovery point, and any
restore older than the local window needs a copy-back first. Raise it where
restore time matters.

## Policies

Every field of a `policies` entry is optional except the targets
(`target_ou_paths` and/or `target_ids`):

| Field | Default | Notes |
|-------|---------|-------|
| `description` | propeller default | |
| `target_ou_paths` / `target_ids` | `[]` | At least one target; OU paths must be keys of `ou_ids` |
| `regions` | `[region]` | |
| `schedule_expression` | `cron(0 2 ? * * *)` | |
| `start_window_minutes` / `completion_window_minutes` | AWS default | |
| `source_vault_name` / `iam_role_name` | `propeller-backup` / `propeller-backup-role` | Contract with the source `backup-vault` defaults |
| `source_retention_days` | `1` | See the trade-off above |
| `copy_to_vault` | `true` | `false` keeps recovery points in the source vault only |
| `copy_vault_arn` | project `copy_vault_arn` | Per-policy override |
| `copy_retention_days` | `30` | Must fall inside the destination Vault Lock window |
| `selection_tag_key` / `selection_tag_values` | `backup` / `["default"]` | |

Use one entry per tier with distinct `selection_tag_values`, so each resource
is picked up by exactly one plan. Policies attached to the same OU merge by
plan name, so keep the keys unique.

## Backup platform

The organization-level backup projects run as their own platform pipeline,
not in the landing zone, so a consumer can choose Control Tower's backup
integration instead without touching the landing-zone pipeline. It deploys
after the landing zone and writes to the **management account**: treat it as
landing-zone-grade (supervised mode or `approval: required`).

```yaml
# platforms/backup/pipeline.yaml
version: "1"
namespace: backup
overlays:
  - projects/${project}
stages:
  - name: backup
    steps:
      - project: backup-org-settings
        source: propeller:backup-org-settings
        target: management
      - project: backup-central-vault
        source: propeller:backup-vault
        target: backup-central            # the dedicated backup account
        inputs:
          - name: "@landing-zone/workload-parameters.organization_id"
            var: organization_id
        outputs:
          - name: vault_arn
          - name: account_id
      - project: backup-policies
        source: propeller:backup-policies
        target: management
        depends_on: [backup-org-settings, backup-central-vault]
        inputs:
          - name: "@landing-zone/workload-parameters.ou_ids"
            var: ou_ids
          - name: backup-central-vault.vault_arn
            var: copy_vault_arn
```

See `config.auto.tfvars.example` for a commented two-tier configuration:

```hcl
# platforms/backup/projects/backup-policies/terraform/config.auto.tfvars
policies = {
  "propeller-backup-daily" = {
    target_ou_paths     = ["Workloads/Prod"]
    copy_retention_days = 35
  }
  "propeller-backup-critical" = {
    target_ou_paths       = ["Workloads/Prod"]
    schedule_expression   = "cron(0 */6 ? * * *)"
    source_retention_days = 3
    copy_retention_days   = 90
    selection_tag_values  = ["critical"]
  }
}
```

The backup platform alone is not enough: every account the policies reach
also needs a **local** `backup-vault` instance, with the vault and role the
policy names. It lives in the platform that owns that workload account, not
here — the backup platform only knows OUs, not the accounts under them.
Without it, jobs start but fail. Deploy the backup platform first, since the
local instance reads the backup account ID from it:

```yaml
# platforms/<workload>/pipeline.yaml — one per workload account in scope
- project: backup-local-vault
  source: propeller:backup-vault
  target: workload-acme-prod
  inputs:
    - name: "@backup/backup-central-vault.account_id"
      var: peer_account_id
  outputs:
    - name: kms_key_arn    # encrypt RDS, EBS, ... with this key
```

See [`backup-vault`](../backup-vault/README.md) and its
`config-local.auto.tfvars.example`.

## What does NOT belong here

- Cold storage transitions — not exposed yet. They must sit on the copy
  action's lifecycle (90-day minimum after transition), never on the short
  source rule.

## References

- [Backup policy syntax and examples](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup_syntax.html)
- [Backup and tag copy](https://docs.aws.amazon.com/aws-backup/latest/devguide/recov-point-create-a-copy.html)
- [Lifecycle](https://docs.aws.amazon.com/aws-backup/latest/APIReference/API_Lifecycle.html)

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
| <a name="module_backup_policy"></a> [backup\_policy](#module\_backup\_policy) | ../../../shared/modules/backup-policy | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_copy_vault_arn"></a> [copy\_vault\_arn](#input\_copy\_vault\_arn) | Default destination vault ARN (e.g. the central backup-vault's vault\_arn). Null disables copies. | `string` | `null` | no |
| <a name="input_ou_ids"></a> [ou\_ids](#input\_ou\_ids) | Map of OU path to OU ID, from @landing-zone/workload-parameters.ou\_ids. Resolves target\_ou\_paths. | `map(string)` | `{}` | no |
| <a name="input_policies"></a> [policies](#input\_policies) | Organizations backup policies to create, keyed by policy name (also the plan<br/>name). Every field is optional except the targets; see README for the field<br/>reference and the defaults' contract with backup-vault. | <pre>map(object({<br/>    description               = optional(string, "AWS Backup policy managed by propeller.")<br/>    target_ou_paths           = optional(list(string), [])<br/>    target_ids                = optional(list(string), [])<br/>    regions                   = optional(list(string), [])<br/>    schedule_expression       = optional(string, "cron(0 2 ? * * *)")<br/>    start_window_minutes      = optional(number)<br/>    completion_window_minutes = optional(number)<br/>    source_vault_name         = optional(string, "propeller-backup")<br/>    source_retention_days     = optional(number, 1)<br/>    iam_role_name             = optional(string, "propeller-backup-role")<br/>    copy_to_vault             = optional(bool, true)<br/>    copy_vault_arn            = optional(string)<br/>    copy_retention_days       = optional(number, 30)<br/>    selection_tag_key         = optional(string, "backup")<br/>    selection_tag_values      = optional(list(string), ["default"])<br/>  }))</pre> | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the management account provider. Also the plan region of policies without regions. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_arns"></a> [policy\_arns](#output\_policy\_arns) | Map of policy name to Organizations backup policy ARN. |
| <a name="output_policy_ids"></a> [policy\_ids](#output\_policy\_ids) | Map of policy name to Organizations backup policy ID. |
| <a name="output_target_ids"></a> [target\_ids](#output\_target\_ids) | Map of policy name to the root, OU or account IDs it is attached to. |
<!-- END_TF_DOCS -->
