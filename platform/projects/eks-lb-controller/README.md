# eks-lb-controller

AWS Load Balancer Controller for an Amazon EKS cluster. Deploys the controller
via Helm with an IRSA role (or EKS Pod Identity) so it can provision ALBs and
NLBs in response to Ingress and `Service type=LoadBalancer` resources.

## What it deploys

- IAM role (IRSA trust towards the cluster OIDC provider) with the controller's
  IAM policy
- Helm release of `aws-load-balancer-controller` from eks-charts

The controller discovers subnets at runtime using the standard
`kubernetes.io/role/elb` (public) and `kubernetes.io/role/internal-elb`
(private) tags on the VPC subnets — no subnet configuration is needed here.

## IAM policy maintenance

The `iam_policy.json` file is a snapshot of the upstream controller's required
permissions. There is no AWS-managed policy for the self-managed (IRSA/Helm)
installation — `AmazonEKSLoadBalancingPolicy` exists but is scoped to EKS Auto
Mode and uses cluster-role-level tags that don't work with IRSA.

When bumping `chart_version`, update `iam_policy.json` from the upstream
release:

```
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v<VERSION>/docs/install/iam_policy.json
```

Current snapshot corresponds to controller **v2.14.1** (chart 3.2.2).

## Pod Identity vs IRSA

`use_pod_identity` defaults to `false` (IRSA/OIDC). Pod Identity is not
supported on pure-Fargate clusters (the agent is a DaemonSet). Switch to Pod
Identity only after adding EC2 node groups and installing the Pod Identity Agent
add-on.

## Ordering

The LB Controller's Helm release needs working in-cluster DNS to become Ready.
In the pipeline, ensure this step runs **after** `eks-addons` (which installs
CoreDNS and the base addons).

## Pipeline inputs

`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`,
`oidc_provider_arn`, `oidc_provider_url` are injected from the `eks-cluster`
step outputs; `vpc_id` from the `workload-vpc` step. Do **not** set them in
`config.auto.tfvars`.

```yaml
- name: eks-lb-controller
  target: workload-account
  depends_on: [eks-addons]
  inputs:
    - name: workload-vpc.vpc_id
      var: vpc_id
    - name: eks-cluster.cluster_name
      var: cluster_name
    - name: eks-cluster.cluster_endpoint
      var: cluster_endpoint
    - name: eks-cluster.cluster_certificate_authority_data
      var: cluster_certificate_authority_data
    - name: eks-cluster.oidc_provider_arn
      var: oidc_provider_arn
    - name: eks-cluster.oidc_provider_url
      var: oidc_provider_url
```

## What does NOT belong here

- The load balancers themselves (ALBs/NLBs) — those are created dynamically by
  the controller when Ingress or Service resources appear in the cluster.
- Cluster infrastructure (control plane, node groups) — that lives in the
  `eks-cluster` project.
- CoreDNS or other EKS managed add-ons — those live in `eks-addons`.
- Observability or autoscaling — those have their own projects.

## References

- [EKS LB Controller installation](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [AWS Load Balancer Controller docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Upstream IAM policy source](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)

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
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |

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
| <a name="input_chart_repository"></a> [chart\_repository](#input\_chart\_repository) | Helm repository the LB Controller chart is pulled from. Defaults to the upstream eks-charts repo. Set to an alternative HTTPS index, an OCI registry (oci://...), or a Helm plugin scheme (s3://, gs://) to source the chart from a mirror. | `string` | `"https://aws.github.io/eks-charts"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Pinned version of the AWS Load Balancer Controller Helm chart from the https://aws.github.io/eks-charts repository. The chart version tracks the controller appVersion (e.g. '3.4.0' installs controller v3.4.0). | `string` | n/a | yes |
| <a name="input_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#input\_cluster\_certificate\_authority\_data) | Base64-encoded certificate authority data for the EKS cluster. Sourced from the eks-cluster project output. Used to configure the helm provider. | `string` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | HTTPS endpoint of the EKS API server. Sourced from the eks-cluster project output. Used to configure the helm provider. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_create_service_account"></a> [create\_service\_account](#input\_create\_service\_account) | Whether Helm creates the LB Controller's Kubernetes ServiceAccount. Set to false when the ServiceAccount is managed externally (pre-created, GitOps, or a Pod Identity association). When false under IRSA, the external ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation. | `bool` | `true` | no |
| <a name="input_iam_policy_json"></a> [iam\_policy\_json](#input\_iam\_policy\_json) | JSON string of the IAM policy to attach to the controller role. When null (the default), the bundled iam\_policy.json matching the default chart\_version is used. Override to supply a policy matching a different controller version or to restrict permissions further. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to install the controller into. | `string` | `"kube-system"` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the IAM OIDC identity provider associated with the EKS cluster. Sourced from the eks-cluster project output. Used as the IRSA trust principal. Required when use\_pod\_identity = false. | `string` | `null` | no |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output. Used in the IRSA sub condition. Required when use\_pod\_identity = false. | `string` | `null` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IRSA role created for the LB Controller. Defaults to '<cluster\_name>-aws-load-balancer-controller'. Override only when the naming convention conflicts with an existing role or IAM path constraint. | `string` | `null` | no |
| <a name="input_service_account_name"></a> [service\_account\_name](#input\_service\_account\_name) | Name of the Kubernetes service account the controller uses. Must match the IRSA trust policy subject or the Pod Identity association. | `string` | `"aws-load-balancer-controller"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_use_pod_identity"></a> [use\_pod\_identity](#input\_use\_pod\_identity) | Whether to use EKS Pod Identity for the Load Balancer Controller. Set to true if the Pod Identity Agent add-on is installed. Not supported on pure-Fargate clusters. Default: false (uses IRSA/OIDC). | `bool` | `false` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the workload VPC. Sourced from the workload-vpc project output. Passed to the LB Controller Helm release as vpcId. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the IRSA role assumed by the LB Controller service account. Null when use\_pod\_identity = true. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the LB Controller IRSA role. Null when use\_pod\_identity = true. |
| <a name="output_service_account_name"></a> [service\_account\_name](#output\_service\_account\_name) | Name of the Kubernetes service account the LB Controller uses. |
<!-- END_TF_DOCS -->
