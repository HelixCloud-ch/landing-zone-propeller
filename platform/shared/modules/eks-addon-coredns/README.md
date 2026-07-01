# eks-addon-coredns

Manages the CoreDNS managed EKS add-on for a single cluster, with first-class
support for scheduling CoreDNS onto Fargate.

## Why a dedicated module

EKS installs CoreDNS as a self-managed add-on on every cluster, pinned to EC2
via the `eks.amazonaws.com/compute-type=ec2` annotation. On a pure-Fargate
cluster (no EC2 nodes) those pods never schedule. Converting CoreDNS to a
*managed* add-on with `configuration_values = { computeType = "Fargate" }`
moves it onto Fargate. The `computeType` key is part of the documented add-on
configuration schema (verify with
`aws eks describe-addon-configuration --addon-name coredns --addon-version <v>`).

A prerequisite is a `kube-system` Fargate profile (created by the
`eks-fargate-profiles` module) so the CoreDNS pods have a profile to land on.

## Usage

```hcl
module "coredns" {
  source = "../../../shared/modules/eks-addon-coredns"

  cluster_name  = module.cluster.cluster_name
  addon_version = "v1.11.4-eksbuild.40"   # pin per the EKS upgrade runbook
  compute_type  = "Fargate"               # omit for EC2-based clusters
}
```

## What does NOT belong here

- No Fargate profile — that is the `eks-fargate-profiles` module's job (this
  module assumes a matching `kube-system` profile already exists when
  `compute_type = "Fargate"`).
- No other add-ons — each add-on gets its own module.

## References

- [Manage CoreDNS for DNS in Amazon EKS clusters](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html)
- [Get started with AWS Fargate — Update CoreDNS](https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html)
- [aws_eks_addon](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_addon_version"></a> [addon\_version](#input\_addon\_version) | Pinned CoreDNS managed add-on version (e.g. 'v1.11.4-eksbuild.40'). Null lets EKS pick the default version for the cluster's Kubernetes release. | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster to install the CoreDNS add-on on. | `string` | n/a | yes |
| <a name="input_compute_type"></a> [compute\_type](#input\_compute\_type) | Compute type CoreDNS pods are scheduled on. Set to 'Fargate' for pure-Fargate clusters (requires a kube-system Fargate profile). Leave null for EC2-based clusters to use the EKS default. | `string` | `null` | no |
| <a name="input_resolve_conflicts_on_create"></a> [resolve\_conflicts\_on\_create](#input\_resolve\_conflicts\_on\_create) | How to resolve field-management conflicts when first creating the add-on over the self-managed CoreDNS that EKS installs by default. | `string` | `"OVERWRITE"` | no |
| <a name="input_resolve_conflicts_on_update"></a> [resolve\_conflicts\_on\_update](#input\_resolve\_conflicts\_on\_update) | How to resolve field-management conflicts on add-on updates. PRESERVE keeps any in-cluster customizations. | `string` | `"PRESERVE"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_addon_arn"></a> [addon\_arn](#output\_addon\_arn) | ARN of the CoreDNS add-on. |
| <a name="output_addon_version"></a> [addon\_version](#output\_addon\_version) | Resolved version of the installed CoreDNS add-on. |
<!-- END_TF_DOCS -->
