# accounts

Runs in the **management account**, `accounts` stage. Vends foundational
accounts that are neither workloads nor Control Tower shared accounts, for
example the CCE backup account, through Service Catalog Account Factory into
the Infrastructure OU.

## Why a separate project

`workload-accounts` only knows the OUs created by `workload-ous`, and
`control-tower-prerequisites` creates raw `aws_organizations_account`
resources meant for Control Tower to take over (Log Archive, Audit, and the
optional Control Tower backup accounts). Accounts vended here are enrolled at
creation, get `AWSControlTowerExecution`, and can therefore receive a
deploy-runner and become pipeline targets like any workload account.

The project only passes the Infrastructure OU wired from the pipeline to the
`ct-account` module, which holds the provisioning logic. The two follow-up steps reuse framework projects:

- `accounts-deploy-runners` (`source: propeller:workload-deploy-runners`)
  provisions the deploy-runner in each account.
- `accounts-registry` (`source: propeller:workload-account-registry`) writes
  `/propeller/accounts/<name>/id`, so `target: <name>` and
  `/accounts.<name>.id` resolve in any pipeline.

## Operational notes

- **Why not the Security OU.** Account Factory only provisions into OUs
  with `AWSControlTowerBaseline` enabled. Control Tower does not apply it to
  the Security OU (its shared accounts carry account-level baselines), so
  provisioning there fails with `InvalidParametersException ... is not
  enrolled in AWS Control Tower` (observed on the test org).
- Tags are never sent to the provisioned product (`aws.notags` provider);
  Account Factory rejects TagOptions and tag updates. See
  [account-network](../account-network/README.md) for the full rationale.
- `retain_physical_resources = true` in `ct-account`: removing an entry
  detaches the provisioned product from state, it does not close the account.
- Account names share the `/propeller/accounts/<name>/` namespace with
  `workload-accounts`. Do not reuse a name across the two projects; the
  registries overwrite each other.
- Provisioning takes 10–20 minutes per account, up to five in parallel.

## What does NOT belong here

- Workload accounts — use `workload-accounts`.
- Accounts Control Tower must take over (Log Archive, Audit, Control Tower
  backup accounts) — those stay in `control-tower-prerequisites`.
- The Network account — still `account-network`, until it is moved here.

## References

- [Provision and manage accounts with Account Factory](https://docs.aws.amazon.com/controltower/latest/userguide/account-factory.html)
- [Types of baselines](https://docs.aws.amazon.com/controltower/latest/userguide/types-of-baselines.html)
- [aws_servicecatalog_provisioned_product](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/servicecatalog_provisioned_product)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.41 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_accounts"></a> [accounts](#module\_accounts) | ../../../shared/modules/ct-account | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [random_id.account_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Accounts to vend into the Infrastructure OU, keyed by name (also the<br/>pipeline target name). sso\_user\_email defaults to email. See README. | <pre>map(object({<br/>    email               = string<br/>    sso_user_email      = optional(string)<br/>    sso_user_first_name = optional(string, "Admin")<br/>    sso_user_last_name  = optional(string, "Account")<br/>  }))</pre> | `{}` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_infrastructure_ou_id"></a> [infrastructure\_ou\_id](#input\_infrastructure\_ou\_id) | Infrastructure OU ID, from ou-infrastructure. | `string` | n/a | yes |
| <a name="input_infrastructure_ou_name"></a> [infrastructure\_ou\_name](#input\_infrastructure\_ou\_name) | Infrastructure OU name, from ou-infrastructure. | `string` | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the Service Catalog API call (must match the Control Tower home region). | `string` | n/a | yes |
| <a name="input_reserved_account_names"></a> [reserved\_account\_names](#input\_reserved\_account\_names) | Names reserved by the framework for other accounts; keys of accounts must not use them. | `set(string)` | <pre>[<br/>  "management",<br/>  "operations",<br/>  "network",<br/>  "log-archive",<br/>  "audit",<br/>  "backup-admin",<br/>  "backup-central"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_ids"></a> [account\_ids](#output\_account\_ids) | Map of account name to account ID. |
| <a name="output_provisioned_product_ids"></a> [provisioned\_product\_ids](#output\_provisioned\_product\_ids) | Map of account name to Service Catalog provisioned product ID. |
<!-- END_TF_DOCS -->
