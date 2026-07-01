# eks-ecr-pull

Attaches cross-account ECR pull permissions to an EKS **Fargate pod execution
role**. Once applied, every pod scheduled under that role can pull images from
the target ECR registry with no per-pod configuration (no `imagePullSecrets`,
no service-account annotations).

## How it works

On EKS Fargate the pod execution role is the runtime identity the platform uses
to pull images and write logs. This project attaches an inline IAM policy to
that role granting `ecr:GetAuthorizationToken` plus the image-pull actions
scoped to the target ECR account. The Fargate data plane then authenticates to
ECR transparently on each pod launch.

The role is not created here — it is supplied by the pipeline from the
`eks-cluster` project. Wire the `default` role via `pod_execution_role_name`, or
a keyed entry from `pod_execution_role_names` to scope ECR access to a specific
Fargate profile group.

## Relationship to rosa-ecr-pull

This is intentionally **separate** from `rosa-ecr-pull`. Both attach a similar
ECR-pull policy, but they target different identities (EKS Fargate pod execution
role vs the ROSA HCP worker node role) and are expected to diverge: EKS offers
several other ways to grant ECR access (IRSA, Pod Identity, node instance
roles) that do not map onto ROSA. Keeping them apart avoids a mixed-platform
project whose upkeep would outweigh the few shared lines.

## Pipeline wiring

```yaml
- name: eks-ecr-pull
  target: workload-account
  inputs:
    - name: eks-cluster.pod_execution_role_name
      var: pod_execution_role_name
```

## Consumer tfvars

```hcl
region         = "eu-central-2"
ecr_account_id = "111111111111"  # account hosting ECR
# ecr_region   = "eu-central-1"  # only if ECR is in another region
```

## What does NOT belong here

- Creating the pod execution role — that is the `eks-cluster` project's job.
- Other ECR-access mechanisms (IRSA, Pod Identity, node instance roles) — those
  warrant their own projects rather than being folded in here.
- ECR repositories or registry policies — see the `ecr` project.

## References

- [Amazon ECR — private registry authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
- [Amazon EKS — Fargate pod execution role](https://docs.aws.amazon.com/eks/latest/userguide/pod-execution-role.html)
- [ecr:GetAuthorizationToken has no resource scope](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonelasticcontainerregistry.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.52.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role_policy.ecr_pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_policy_document.ecr_pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_ecr_account_id"></a> [ecr\_account\_id](#input\_ecr\_account\_id) | AWS account ID that hosts the shared ECR registry. Must be set in config.auto.tfvars; no default. | `string` | n/a | yes |
| <a name="input_ecr_region"></a> [ecr\_region](#input\_ecr\_region) | AWS region of the shared ECR account. Defaults to var.region when null. | `string` | `null` | no |
| <a name="input_pod_execution_role_name"></a> [pod\_execution\_role\_name](#input\_pod\_execution\_role\_name) | Name of the Fargate pod execution role the ECR pull policy is attached to. Sourced from the eks-cluster project output pod\_execution\_role\_name (or a keyed entry of pod\_execution\_role\_names). | `string` | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the Fargate pod execution role lives. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->