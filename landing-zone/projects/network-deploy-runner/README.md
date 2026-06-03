# network-deploy-runner

Runs in the **management account**, `foundation` stage (after `account-network` and `bootstrap-parameters`).

Provisions the `deploy-runner` Service Catalog product in the Network account by assuming
`AWSControlTowerExecution` there. The Network account has no CodeBuild project yet at this
point — that is exactly what this project creates.

After this project completes, the autopilot can trigger infrastructure runs in the Network
account by assuming `deploy-runner-run-role` and starting the `deploy-runner` CodeBuild project.

## What it does

- Associates the Terraform execution role (`AWSControlTowerExecution`) with the Service Catalog
  portfolio so it can call `provision-product`.
- Provisions the `deploy-runner` CloudFormation product, which creates:
  - S3 bucket `state-iac-{account}-{region}-an` for Terraform state
  - CodeBuild project `deploy-runner` with an `AdministratorAccess` service role
  - IAM role `deploy-runner-run-role` trusted by `propeller-autopilot-role` in the operations account

All pipeline inputs (`portfolio_id`, `s3_source_bucket`, `caller_arn`, `caller_account_id`) are
wired automatically from `bootstrap-parameters` and `account-network`. No values need to be
hardcoded in `config.auto.tfvars`.

## Module structure

The Service Catalog logic lives in `terraform/modules/sc-deploy-runner/` so it can be reused
for future accounts (tenant accounts, sandbox accounts) once the propeller engine supports
shared modules. The root module is a thin wrapper that supplies the cross-account provider
and passes variables through.

```
network-deploy-runner/
├── project.yaml
├── README.md
└── terraform/
    ├── main.tf           # calls ./modules/sc-deploy-runner
    ├── variables.tf
    ├── providers.tf      # assumes AWSControlTowerExecution in the Network account
    ├── outputs.tf
    ├── versions.tf
    └── modules/
        └── sc-deploy-runner/
            ├── main.tf   # aws_servicecatalog_principal_portfolio_association + provisioned_product
            ├── variables.tf
            ├── outputs.tf
            └── versions.tf
```

## Operational notes

**First apply:** Terraform blocks until the CloudFormation stack reaches `CREATE_COMPLETE`
(typically under 2 minutes for this product).

**Artifact upgrades:** `provisioning_artifact_name` and `provisioning_artifact_id` are under
`lifecycle.ignore_changes`. To upgrade, run `update-provisioned-product` via the chore script
using the `provisioned_product_id` output.

**Reusing for other accounts:** Copy `terraform/modules/sc-deploy-runner/` into a new project
(e.g. `sandbox-deploy-runner`), create a thin root module and a matching `config.auto.tfvars`.
The module will be moved to a shared location once the propeller engine supports it.

## What does NOT belong here

- Portfolio creation and sharing — done at bootstrap via `bootstrap/scripts/create-portfolio.sh` and `share-portfolio.sh`.
- The deploy-runner in operations or management — provisioned at bootstrap, not pipeline-managed.
- Terraform state for the Network account after this project runs — managed by the `deploy-runner` CodeBuild project in the Network account itself.

## References

- [Service Catalog Deploy Runner](../../../../notes/wiki/aws/service-catalog-deploy-runner.md)
- [Bootstrap Parameters](../bootstrap-parameters/README.md)
- [aws_servicecatalog_provisioned_product](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/servicecatalog_provisioned_product)
- [aws_servicecatalog_principal_portfolio_association](https://registry.terraform.io/providers/hashicorp/aws/6.41.0/docs/resources/servicecatalog_principal_portfolio_association)

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
| <a name="module_deploy_runner"></a> [deploy\_runner](#module\_deploy\_runner) | ./modules/sc-deploy-runner | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_assume_role_name"></a> [assume\_role\_name](#input\_assume\_role\_name) | IAM role to assume in the Network account. AWSControlTowerExecution is present in all CT-enrolled accounts and is used here because the deploy-runner does not yet exist in the Network account. | `string` | `"AWSControlTowerExecution"` | no |
| <a name="input_caller_account_id"></a> [caller\_account\_id](#input\_caller\_account\_id) | AWS account ID of the operations account (CallerAccountId parameter). Wired from SSM /accounts.operations.id via the propeller pipeline. | `string` | `""` | no |
| <a name="input_caller_arn"></a> [caller\_arn](#input\_caller\_arn) | ARN of the autopilot role that will assume deploy-runner-run-role in the Network account (CallerARN parameter). Wired from bootstrap-parameters outputs via the propeller pipeline. | `string` | `""` | no |
| <a name="input_cb_project_name"></a> [cb\_project\_name](#input\_cb\_project\_name) | Name of the CodeBuild project (ProjectName parameter). | `string` | `"deploy-runner"` | no |
| <a name="input_create_bucket"></a> [create\_bucket](#input\_create\_bucket) | Whether to create the IaC state S3 bucket. Set to false if it already exists. | `bool` | `true` | no |
| <a name="input_network_account_id"></a> [network\_account\_id](#input\_network\_account\_id) | AWS account ID of the Network account. Wired from account-network outputs via the propeller pipeline. | `string` | n/a | yes |
| <a name="input_portfolio_id"></a> [portfolio\_id](#input\_portfolio\_id) | ID of the Service Catalog portfolio (e.g. port-xxxx). Wired from bootstrap-parameters outputs via the propeller pipeline. Used both for the principal association and as path\_id when provisioning. | `string` | n/a | yes |
| <a name="input_product_id"></a> [product\_id](#input\_product\_id) | ID of the Service Catalog product (e.g. prod-xxxx). Wired from bootstrap-parameters outputs via the propeller pipeline. | `string` | n/a | yes |
| <a name="input_provisioned_product_name"></a> [provisioned\_product\_name](#input\_provisioned\_product\_name) | Name for the provisioned product in the Network account. Defaults to the name used in all other accounts. | `string` | `"deploy-runner"` | no |
| <a name="input_provisioning_artifact_id"></a> [provisioning\_artifact\_id](#input\_provisioning\_artifact\_id) | ID of the provisioning artifact (product version) to deploy (e.g. pa-xxxx). Wired from bootstrap-parameters, which resolves the latest active DEFAULT artifact. Changing this value triggers an in-place update of the provisioned product. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the Service Catalog API call (must match the landing zone home region). | `string` | n/a | yes |
| <a name="input_s3_source_bucket"></a> [s3\_source\_bucket](#input\_s3\_source\_bucket) | Name of the source S3 bucket in the operations account (CBS3SourceBucket parameter). Wired from bootstrap-parameters outputs via the propeller pipeline. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied via provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_provisioned_product_id"></a> [provisioned\_product\_id](#output\_provisioned\_product\_id) | Service Catalog provisioned product ID for the deploy-runner in the Network account. |
| <a name="output_provisioned_product_status"></a> [provisioned\_product\_status](#output\_provisioned\_product\_status) | Status of the Service Catalog provisioned product. |
<!-- END_TF_DOCS -->
