# eks-addon-lb-controller

Installs the AWS Load Balancer Controller into an EKS cluster: the IRSA role,
its IAM policy, and the Helm release. Does NOT create any ALB/NLB — it installs
the controller that provisions them on demand from `Ingress` and
`Service type=LoadBalancer` objects.

## Why a dedicated module

The controller is Helm-based (needs the `helm` provider and cluster auth) and
customer-specific — not every cluster exposes anything via load balancers. It
is deliberately separate from the EKS-managed add-ons, which only need the
`aws` provider. Keeping it as its own module lets a consumer project opt in or
out with a single module block.

## IAM policy

The controller's IAM policy is bundled as `iam_policy.json`, pinned to a
specific upstream controller release (currently v3.4.0). When bumping
`chart_version`, refresh the JSON from the matching release tag:

```
curl -o iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v<X.Y.Z>/docs/install/iam_policy.json
```

## Chart source

The chart name is fixed (`aws-load-balancer-controller`) but `chart_repository`
selects where it is pulled from. It defaults to the upstream
`https://aws.github.io/eks-charts`; override it to point at an internal mirror —
an HTTPS chart index, an OCI registry (`oci://...`), or a Helm plugin scheme
(`s3://`, `gs://`, which require the corresponding Helm plugin on the runner).

## ServiceAccount ownership

`create_service_account` (default `true`) controls whether Helm creates the
controller's ServiceAccount. Set it to `false` when the ServiceAccount is
managed outside the chart (pre-created by a separate resource, a GitOps tool,
or a Pod Identity association that owns it) — otherwise the release fails on an
ownership conflict.

Under IRSA the `eks.amazonaws.com/role-arn` annotation is applied *through* the
chart-managed ServiceAccount, so it is only injected when
`create_service_account = true`. When `false` under IRSA, the external
ServiceAccount **must already carry** that annotation pointing at this module's
`role_arn` output; the module cannot annotate a ServiceAccount it does not
create. Under Pod Identity no annotation is needed.

## Usage

```hcl
module "lb_controller" {
  source = "../../../shared/modules/eks-addon-lb-controller"

  cluster_name      = module.cluster.cluster_name
  region            = var.region
  vpc_id            = var.vpc_id
  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_provider_url = module.cluster.oidc_provider_url
  chart_version     = "3.4.0"
}
```

Requires CoreDNS to be running first (the controller's webhook needs in-cluster
DNS). In a pipeline, sequence this after the CoreDNS add-on.

## References

- [Install AWS Load Balancer Controller with Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [aws-load-balancer-controller releases (chart + IAM policy)](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases)

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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.52.0 |
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

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm repository the chart is pulled from. Defaults to the upstream eks-charts repo. Set to an alternative HTTPS index, an OCI registry (oci://...), or a Helm plugin scheme (s3://, gs://) to source the chart from a mirror. The chart name is always 'aws-load-balancer-controller'. | `string` | `"https://aws.github.io/eks-charts"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of the aws-load-balancer-controller Helm chart from the https://aws.github.io/eks-charts repository. Keep in sync with the bundled iam\_policy.json (both pinned to the same controller release). The chart version tracks the controller appVersion (e.g. '3.4.0' installs controller v3.4.0). Supports Kubernetes 1.22 and later, including 1.36. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster the controller manages load balancers for. | `string` | n/a | yes |
| <a name="input_create_service_account"></a> [create\_service\_account](#input\_create\_service\_account) | Whether Helm creates the controller's Kubernetes ServiceAccount. Set to false when the ServiceAccount is managed externally (pre-created, GitOps, or a Pod Identity association that owns it) to avoid an ownership conflict. When false under IRSA, the external ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation for role\_arn — this module cannot annotate a ServiceAccount it does not create. | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to install the controller into. | `string` | `"kube-system"` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the cluster IAM OIDC provider. Required only when use\_pod\_identity = false. Used as the IRSA trust principal for the controller's service account role. | `string` | `null` | no |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the cluster OIDC provider, without the https:// prefix. Required only when use\_pod\_identity = false. Used in the IRSA sub/aud trust conditions. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster. Passed to the controller as the 'region' Helm value. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IRSA role for the controller. Defaults to '<cluster\_name>-aws-load-balancer-controller'. Required only when use\_pod\_identity = false. | `string` | `null` | no |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Name of the Kubernetes service account the controller uses. Must match the IRSA trust policy subject (when using IRSA) or the service account associated with the Pod Identity (when using Pod Identity). | `string` | `"aws-load-balancer-controller"` | no |
| <a name="input_use_pod_identity"></a> [use\_pod\_identity](#input\_use\_pod\_identity) | Whether to use EKS Pod Identity instead of IRSA/OIDC for IAM credentials. Set to true for clusters with the Pod Identity Agent add-on. | `bool` | `false` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the cluster VPC. Passed to the controller as the 'vpcId' Helm value. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IRSA role assumed by the controller's service account. Null when use\_pod\_identity = true. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the IRSA role. Null when use\_pod\_identity = true. |
| <a name="output_service_account_name"></a> [service\_account\_name](#output\_service\_account\_name) | Name of the Kubernetes service account the controller uses. |
<!-- END_TF_DOCS -->
