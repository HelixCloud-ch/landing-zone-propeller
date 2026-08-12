# eks-addon-autoscaler

Deploys the Kubernetes [Cluster Autoscaler](https://github.com/kubernetes/autoscaler)
on an EKS cluster with EC2 managed node groups.

## What it deploys

- IRSA role with permissions to describe and scale the cluster's Auto Scaling
  Groups (unless `use_pod_identity = true` or `existing_role_arn` is set)
- Helm release of `cluster-autoscaler` with `autoDiscovery.clusterName` so it
  finds all managed node groups automatically

## IAM identity modes

| `use_pod_identity` | `existing_role_arn` | Behavior |
|----|----|----|
| `false` | `null` | Creates IRSA role + policy, annotates SA (default) |
| `false` | set | No IAM resources created; annotates SA with the provided ARN |
| `true` | any | No IRSA role, no annotation. Auth is handled by a Pod Identity association created externally |

When using Pod Identity, create an `aws_eks_pod_identity_association` in a
separate step referencing this project's `service_account_name` output.

## Where it runs

Deployed on the workload account, after `eks-cluster` (needs cluster outputs)
and after `eks-addons` (needs working DNS + vpc-cni).

## Pipeline inputs

| Input | Source |
|-------|--------|
| `cluster_name` | `eks-cluster.cluster_name` |
| `cluster_endpoint` | `eks-cluster.cluster_endpoint` |
| `cluster_certificate_authority_data` | `eks-cluster.cluster_certificate_authority_data` |
| `oidc_provider_arn` | `eks-cluster.oidc_provider_arn` |
| `oidc_provider_url` | `eks-cluster.oidc_provider_url` |

## Sleep interaction

The `sleep-scale-zero` recipe in `eks-cluster` scales node groups to 0. The
autoscaler will immediately try to scale them back up if pending pods exist.
To prevent this, the sleep recipe should scale the autoscaler Deployment to 0
replicas before scaling node groups (and restore it during wake). This is
handled in the `eks-cluster` justfile.

## Future: Karpenter

A future `eks-karpenter` project can replace this one in the pipeline. Karpenter
requires its own IAM/SQS/instance-profile surface and is not implemented yet.

## References

- [Cluster Autoscaler AWS cloud provider](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [CA compatibility matrix](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#releases)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.58.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.2.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.this](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.autoscaler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm repository for the cluster-autoscaler chart. Override to a mirror in air-gapped environments. | `string` | `"https://kubernetes.github.io/autoscaler"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the cluster-autoscaler Helm chart (e.g. '9.57.0'). Pin to match the EKS Kubernetes version per the CA compatibility matrix. | `string` | n/a | yes |
| <a name="input_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#input\_cluster\_certificate\_authority\_data) | Base64-encoded certificate authority data for the EKS cluster. Sourced from the eks-cluster project output. Used to configure the helm provider. | `string` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | HTTPS endpoint of the EKS API server. Sourced from the eks-cluster project output. Used to configure the helm provider. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_create_service_account"></a> [create\_service\_account](#input\_create\_service\_account) | Whether Helm creates the Kubernetes ServiceAccount for the autoscaler. Set to false when the ServiceAccount is managed externally (GitOps, another Terraform step, or a Pod Identity association). When false, the existing ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation. | `bool` | `true` | no |
| <a name="input_existing_role_arn"></a> [existing\_role\_arn](#input\_existing\_role\_arn) | ARN of a pre-existing IAM role to use instead of creating one. When set, no role or policy resources are created — the provided role is annotated on the ServiceAccount directly. Useful when the role is managed outside this project or shared across clusters. | `string` | `null` | no |
| <a name="input_extra_set"></a> [extra\_set](#input\_extra\_set) | Additional Helm set values passed to the release. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Container image repository for the autoscaler. Override to an ECR mirror in air-gapped environments. Null uses the chart default. | `string` | `null` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Container image tag for the autoscaler. Null uses the chart's appVersion. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy the autoscaler into. | `string` | `"kube-system"` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the IAM OIDC provider for the cluster. Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IRSA role for the autoscaler. Defaults to '<cluster\_name>-cluster-autoscaler'. | `string` | `null` | no |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Name of the Kubernetes service account the autoscaler uses. | `string` | `"cluster-autoscaler"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_use_pod_identity"></a> [use\_pod\_identity](#input\_use\_pod\_identity) | Whether to use EKS Pod Identity instead of IRSA/OIDC. When true, no IRSA role is created and no role-arn annotation is set on the ServiceAccount. The Pod Identity association must be created separately (e.g. via aws\_eks\_pod\_identity\_association). | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IAM role for the Cluster Autoscaler. Null when use\_pod\_identity = true and no existing\_role\_arn is provided. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IAM role for the Cluster Autoscaler. Null when the role is not managed by this project. |
| <a name="output_service_account_name"></a> [service\_account\_name](#output\_service\_account\_name) | Name of the Kubernetes service account used by the autoscaler. |
<!-- END_TF_DOCS -->
