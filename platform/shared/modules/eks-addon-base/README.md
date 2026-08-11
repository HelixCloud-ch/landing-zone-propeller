# eks-addon-base

Generic EKS managed add-on module for addons that only need a version pin and
resolve-conflicts semantics — no complex `configuration_values`.

Intended for: `vpc-cni`, `kube-proxy`, `eks-pod-identity-agent`,
`aws-ebs-csi-driver`, and similar.

Addons with non-trivial configuration have their own dedicated modules:
- `eks-addon-coredns` — `computeType` for Fargate
- `eks-addon-lb-controller` — Helm release + IRSA
- `eks-obs-cloudwatch-addon` — IRSA + Application Signals config

## Version resolution

When `addon_version` is null, the module resolves the most recent compatible
version for the cluster's Kubernetes release via `data.aws_eks_addon_version`.
When a version is supplied, it is used as-is.

## Usage

```hcl
module "vpc_cni" {
  source       = "../../../shared/modules/eks-addon-base"
  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"
  addon_version = "v1.19.5-eksbuild.1"  # or null for latest
}

module "kube_proxy" {
  source       = "../../../shared/modules/eks-addon-base"
  cluster_name = var.cluster_name
  addon_name   = "kube-proxy"
}
```

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
| [aws_eks_addon_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_addon_version) | data source |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_addon_name"></a> [addon\_name](#input\_addon\_name) | Name of the EKS add-on (e.g. 'vpc-cni', 'kube-proxy', 'eks-pod-identity-agent', 'aws-ebs-csi-driver'). | `string` | n/a | yes |
| <a name="input_addon_version"></a> [addon\_version](#input\_addon\_version) | Pinned version of the add-on. Null resolves to the most recent compatible version for the cluster's Kubernetes release. | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster to install the add-on on. | `string` | n/a | yes |
| <a name="input_configuration_values"></a> [configuration\_values](#input\_configuration\_values) | JSON-encoded configuration\_values. Null uses EKS defaults. For non-trivial config, use a dedicated addon module instead. | `string` | `null` | no |
| <a name="input_preserve"></a> [preserve](#input\_preserve) | Whether to preserve the add-on's resources when deleting from Terraform. | `bool` | `false` | no |
| <a name="input_resolve_conflicts_on_create"></a> [resolve\_conflicts\_on\_create](#input\_resolve\_conflicts\_on\_create) | How to resolve field-management conflicts when creating the add-on. | `string` | `"OVERWRITE"` | no |
| <a name="input_resolve_conflicts_on_update"></a> [resolve\_conflicts\_on\_update](#input\_resolve\_conflicts\_on\_update) | How to resolve field-management conflicts on add-on updates. | `string` | `"OVERWRITE"` | no |
| <a name="input_service_account_role_arn"></a> [service\_account\_role\_arn](#input\_service\_account\_role\_arn) | ARN of an IAM role to bind to the add-on's service account. Null uses the node IAM role permissions. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the add-on resource. Merged with provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_addon_arn"></a> [addon\_arn](#output\_addon\_arn) | ARN of the add-on. |
| <a name="output_addon_version"></a> [addon\_version](#output\_addon\_version) | Resolved version of the installed add-on. |
| <a name="output_latest_compatible_version"></a> [latest\_compatible\_version](#output\_latest\_compatible\_version) | Most recent compatible version for the cluster's Kubernetes release. Useful for planning upgrades. |
<!-- END_TF_DOCS -->
