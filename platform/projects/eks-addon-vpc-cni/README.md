# eks-addon-vpc-cni

Amazon VPC CNI managed EKS add-on for an EC2 node-group cluster, with a
dedicated IAM role for the `aws-node` identity (IRSA or Pod Identity).

## What it deploys

- An IAM role (`<cluster_name>-vpc-cni`) carrying `AmazonEKS_CNI_Policy`,
  scoped to the `aws-node` identity
- The `vpc-cni` managed EKS add-on via the generic `eks-addon-base` module,
  bound to that role via IRSA (default) or Pod Identity

## Why a dedicated role, scoped to `aws-node`

Per [AWS's own
recommendation](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html),
CNI permissions are scoped to the `aws-node` identity rather than attached to
the shared node role. This means EC2 instances don't inherit ENI/IP-assignment
permissions they don't need — every other process on the node runs under the
node role's narrower permission set.

## IRSA vs. Pod Identity

vpc-cni supports both mechanisms — see [AWS's vpc-cni permissions
guide](https://docs.aws.amazon.com/help-panel/eks/latest/console/hp-add-ons-vpc-cni-iam.html),
which explicitly recommends either. `use_pod_identity` defaults to `false`
(IRSA/OIDC, via `service_account_role_arn` on the addon and an
`sts:AssumeRoleWithWebIdentity` trust policy). Set `use_pod_identity = true`
to use `pod_identity_association` instead (trust on
`pods.eks.amazonaws.com`) — this requires the `eks-pod-identity-agent` addon
to already be installed (enable it in `eks-addons`'s `base_addons` map first).

## Where it runs

Fargate-only clusters don't need this project — the CNI on Fargate is a
built-in control-plane mechanism, not a DaemonSet with a ServiceAccount. Only
wire this in for EC2 node-group or mixed-mode clusters.

## Pipeline inputs

`cluster_name`, `oidc_provider_arn`, `oidc_provider_url` are injected from the
`eks-cluster` step output. Do **not** set them in `config.auto.tfvars`.

```yaml
- name: eks-addon-vpc-cni
  target: workload-account
  inputs:
    - name: eks-cluster.cluster_name
      var: cluster_name
    - name: eks-cluster.oidc_provider_arn
      var: oidc_provider_arn
    - name: eks-cluster.oidc_provider_url
      var: oidc_provider_url
```

## What does NOT belong here

- CoreDNS or other config-light managed add-ons (kube-proxy,
  eks-pod-identity-agent) — those live in `eks-addons`.
- The node role or node groups themselves — those live in `eks-cluster`.
- AWS Load Balancer Controller, Autoscaler, Observability — those have their
  own dedicated projects.

## References

- [Amazon EKS node IAM role](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html)
- [Amazon VPC CNI plugin for Kubernetes](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)

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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vpc_cni"></a> [vpc\_cni](#module\_vpc\_cni) | ../../../shared/modules/eks-addon-base | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.assume_irsa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.assume_pod_identity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_addon_version"></a> [addon\_version](#input\_addon\_version) | Pinned version of the vpc-cni managed add-on (e.g. "v1.19.5-eksbuild.1"). Null lets EKS pick the default. | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_configuration_values"></a> [configuration\_values](#input\_configuration\_values) | JSON-encoded configuration\_values for the vpc-cni add-on. Null uses EKS defaults. | `string` | `null` | no |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the IAM OIDC identity provider associated with the EKS cluster. Sourced from the eks-cluster project output. Required when use\_pod\_identity = false. | `string` | `null` | no |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output. Required when use\_pod\_identity = false. | `string` | `null` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IRSA role for vpc-cni. Defaults to '<cluster\_name>-vpc-cni'. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_use_pod_identity"></a> [use\_pod\_identity](#input\_use\_pod\_identity) | Whether to use EKS Pod Identity instead of IRSA/OIDC. vpc-cni supports both. Requires the eks-pod-identity-agent add-on to be installed. Default: false (uses IRSA/OIDC). | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_addon_version"></a> [addon\_version](#output\_addon\_version) | Resolved version of the installed vpc-cni add-on. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IRSA role for the vpc-cni add-on's aws-node ServiceAccount. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IRSA role for vpc-cni. |
<!-- END_TF_DOCS -->
