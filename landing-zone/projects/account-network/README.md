# account-network

Runs in the **management account**, `foundation` stage (after `ou-infrastructure`).

Vends the Network account via the **Service Catalog Account Factory** and places it in the Infrastructure OU. The account is used to host the network plane (Transit Gateway, VPCs, routing). All pipeline projects that target `network` depend on this account existing.

## What it does

Calls the `ct-account` module which provisions an `aws_servicecatalog_provisioned_product` against the `AWS Control Tower Account Factory` product. Service Catalog creates the AWS account directly into the target OU and synchronously waits for full CT enrollment (all baseline StackSets deployed) before returning.

Tags are intentionally not passed to the provisioned product. AWS guidance is explicit that the `AWS Control Tower Account Factory` product must not receive tags — per [Provision accounts in the Service Catalog console](https://docs.aws.amazon.com/controltower/latest/userguide/provision-as-end-user.html): "Don't define TagOptions and don't enable Notifications, otherwise the account can fail to be provisioned." On top of that, the product has a Resource Update Constraint that rejects any tag update after provisioning with a `ValidationException`. The `ct-account` module therefore uses the `aws.notags` provider alias (no `default_tags`) so no tags are ever sent to the SC API, and sets `lifecycle.ignore_changes = [tags, tags_all]` so Terraform never tries to reconcile tags on products that already carry them. There is no supported way to tag the underlying account resources through this product.

## Operational notes

- `retain_physical_resources = true` is mandatory — destroying this resource without it would attempt to close the AWS account.
- `AccountEmail` is immutable after provisioning; the module uses `use_previous_value = true` on that parameter.
- Provisioning takes 10–20 minutes (CT baselines must deploy fully). The pipeline timeout should exceed 30 minutes for this step.
- `ou_id` and `ou_name` are wired from `ou-infrastructure` outputs via the pipeline — they cannot be hardcoded in `config.auto.tfvars`.

## What does NOT belong here

- Network resources (TGW, VPCs, subnets) — those belong in the `network` stage projects.
- The deploy-runner provisioning in the Network account — that is `network-deploy-runner`.

## References

- [Account Vending operations guide](../../../../notes/wiki/operations/account-vending.md)
- [aws_servicecatalog_provisioned_product](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/servicecatalog_provisioned_product)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 6.41.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_account"></a> [account](#module\_account) | ./modules/ct-account | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_email"></a> [account\_email](#input\_account\_email) | Root email address for the Network account. | `string` | n/a | yes |
| <a name="input_account_name"></a> [account\_name](#input\_account\_name) | Friendly name for the Network account. | `string` | `"Network"` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Pipeline-wide tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_ou_id"></a> [ou\_id](#input\_ou\_id) | ID of the target OU. Wired from ou-infrastructure outputs via the propeller pipeline. | `string` | n/a | yes |
| <a name="input_ou_name"></a> [ou\_name](#input\_ou\_name) | Name of the OU where the Network account will be placed (typically the Infrastructure OU). | `string` | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Framework-managed tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the Service Catalog API call (must match the Control Tower home region). | `string` | n/a | yes |
| <a name="input_sso_user_email"></a> [sso\_user\_email](#input\_sso\_user\_email) | Email for the SSO user that Account Factory creates. Defaults to account\_email when empty. | `string` | `""` | no |
| <a name="input_sso_user_first_name"></a> [sso\_user\_first\_name](#input\_sso\_user\_first\_name) | First name for the Account Factory SSO user. | `string` | `"Network"` | no |
| <a name="input_sso_user_last_name"></a> [sso\_user\_last\_name](#input\_sso\_user\_last\_name) | Last name for the Account Factory SSO user. | `string` | `"Account"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Per-project tags applied to all resources via provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | AWS account ID of the Network account. |
| <a name="output_provisioned_product_id"></a> [provisioned\_product\_id](#output\_provisioned\_product\_id) | Service Catalog provisioned product ID for the Network account. |
<!-- END_TF_DOCS -->
