# eks-addons

Cluster add-ons for an Amazon EKS cluster. Installs the CoreDNS managed add-on
and, optionally, the AWS Load Balancer Controller. It is a thin pipeline wrapper
around the `eks-addon-coredns` and `eks-addon-lb-controller` shared modules —
all resource logic lives in those modules.

## What it deploys

| Add-on | Mechanism | Toggle |
|--------|-----------|--------|
| CoreDNS | Managed EKS add-on (`aws_eks_addon`) | `install_coredns` (default true) |
| AWS Load Balancer Controller | Helm release + IRSA/Pod Identity | `install_lb_controller` (default false) |

**CoreDNS.** Managed here only when `install_coredns = true`. It is **required
on pure-Fargate clusters** — the default self-managed CoreDNS deployment cannot
schedule without nodes, so the managed add-on (with `coredns_compute_type =
"Fargate"`) is what provides in-cluster DNS. On **EC2 node-group clusters** EKS
already ships a working CoreDNS, so managing the add-on is optional; enable it
only to pin or upgrade the version deliberately.

**Load Balancer Controller.** Opt-in; enable it only on clusters that expose
Ingress or `Service type=LoadBalancer`.

## Compute type

`coredns_compute_type` controls where CoreDNS pods schedule. Set it to
`Fargate` on pure-Fargate clusters — this requires a `kube-system` Fargate
profile on the cluster (scoped to `k8s-app=kube-dns`), provisioned by the
`eks-cluster` project. Leave it null on EC2-based clusters to use the EKS
default.

## Ordering

The Load Balancer Controller's Helm release needs working in-cluster DNS to
become Ready (`helm_release` waits by default). On a fresh pure-Fargate cluster
a single apply can race the CoreDNS add-on rollout, so the controller module
has an explicit `depends_on` the CoreDNS module. This is a module-level
dependency, so it is coarse (the whole controller module waits for the whole
CoreDNS module), but it is the only scenario where the ordering matters — on
EC2 clusters DNS is already up. When `install_coredns = false` the reference
resolves to an empty set and the dependency becomes a no-op.

On a pure-Fargate cluster, after the first apply you may need to roll CoreDNS so
it reschedules onto Fargate:

```bash
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status  deployment/coredns -n kube-system
```

## Pipeline inputs

`cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`,
`oidc_provider_arn`, and `oidc_provider_url` are injected from the `eks-cluster`
step outputs; `vpc_id` from the `workload-vpc` step. Do **not** set them in
`config.auto.tfvars`. The `oidc_provider_*` and `vpc_id` inputs are only
consumed when `install_lb_controller = true` (and, for OIDC, when
`lbc_use_pod_identity = false`).

```yaml
- name: eks-addons
  target: workload-account
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

## Pod Identity vs IRSA

`lbc_use_pod_identity` defaults to IRSA/OIDC. Pod Identity is not supported on
pure-Fargate clusters (the agent is a DaemonSet). Switch to Pod Identity only
after adding EC2 node groups and installing the Pod Identity Agent add-on.

## What does NOT belong here

- Cluster infrastructure (control plane, Fargate profiles, node groups) — that
  lives in the `eks-cluster` project.
- `kube-proxy` / `vpc-cni` — EKS self-manages these unless you adopt them as
  managed add-ons deliberately.
- Cross-account ECR pull policy — that lives in the ECR-pull project.
- IAM policies or roles for unrelated services.

## References

- [EKS CoreDNS management](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html)
- [EKS Pod Identity (not supported on Fargate)](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [AWS Load Balancer Controller docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS upgrade runbook](../../../../notes/wiki/operations/eks-upgrade-runbook.md)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_coredns"></a> [coredns](#module\_coredns) | ../../../shared/modules/eks-addon-coredns | n/a |
| <a name="module_lb_controller"></a> [lb\_controller](#module\_lb\_controller) | ../../../shared/modules/eks-addon-lb-controller | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#input\_cluster\_certificate\_authority\_data) | Base64-encoded certificate authority data for the EKS cluster. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers. | `string` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | HTTPS endpoint of the EKS API server. Sourced from the eks-cluster project output. Used to configure the kubernetes and helm providers. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Sourced from the eks-cluster project output. | `string` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_coredns_compute_type"></a> [coredns\_compute\_type](#input\_coredns\_compute\_type) | Compute type CoreDNS pods are scheduled on. Set to "Fargate" for pure-Fargate clusters (requires a kube-system Fargate profile on the cluster). Leave null for EC2-based clusters to use the EKS default. | `string` | `null` | no |
| <a name="input_coredns_version"></a> [coredns\_version](#input\_coredns\_version) | Pinned version of the CoreDNS managed EKS add-on (e.g. "v1.11.4-eksbuild.40"). Bump in lockstep with the cluster Kubernetes version per the EKS upgrade runbook. Null lets EKS pick the default for the cluster's Kubernetes release. Ignored when install\_coredns is false. | `string` | `null` | no |
| <a name="input_install_coredns"></a> [install\_coredns](#input\_install\_coredns) | Whether to manage the CoreDNS EKS add-on here. Must be true on pure-Fargate clusters (the default self-managed CoreDNS cannot schedule without nodes). On EC2 node-group clusters EKS provides a working CoreDNS by default, so enable this only to pin or upgrade the add-on version deliberately. | `bool` | `true` | no |
| <a name="input_install_lb_controller"></a> [install\_lb\_controller](#input\_install\_lb\_controller) | Whether to install the AWS Load Balancer Controller. Set to false for clusters that only need internal DNS and do not require Ingress or Service type=LoadBalancer. | `bool` | `false` | no |
| <a name="input_lbc_chart_repository"></a> [lbc\_chart\_repository](#input\_lbc\_chart\_repository) | Helm repository the LB Controller chart is pulled from. Defaults to the upstream eks-charts repo. Set to an alternative HTTPS index, an OCI registry (oci://...), or a Helm plugin scheme (s3://, gs://) to source the chart from a mirror. | `string` | `"https://aws.github.io/eks-charts"` | no |
| <a name="input_lbc_chart_version"></a> [lbc\_chart\_version](#input\_lbc\_chart\_version) | Pinned version of the AWS Load Balancer Controller Helm chart from the https://aws.github.io/eks-charts repository. The chart version tracks the controller appVersion (e.g. "3.4.0" installs controller v3.4.0). Required only when install\_lb\_controller = true. | `string` | `null` | no |
| <a name="input_lbc_create_service_account"></a> [lbc\_create\_service\_account](#input\_lbc\_create\_service\_account) | Whether Helm creates the LB Controller's Kubernetes ServiceAccount. Set to false when the ServiceAccount is managed externally (pre-created, GitOps, or a Pod Identity association). When false under IRSA, the external ServiceAccount must already carry the eks.amazonaws.com/role-arn annotation. | `bool` | `true` | no |
| <a name="input_lbc_role_name"></a> [lbc\_role\_name](#input\_lbc\_role\_name) | Name of the IRSA role created for the LB Controller. Defaults to '<cluster\_name>-aws-load-balancer-controller'. Override only when the naming convention conflicts with an existing role or IAM path constraint. | `string` | `null` | no |
| <a name="input_lbc_use_pod_identity"></a> [lbc\_use\_pod\_identity](#input\_lbc\_use\_pod\_identity) | Whether to use EKS Pod Identity for the Load Balancer Controller. Set to true if the Pod Identity Agent add-on is installed. Not supported on pure-Fargate clusters. Default: false (uses IRSA/OIDC). | `bool` | `false` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the IAM OIDC identity provider associated with the EKS cluster. Sourced from the eks-cluster project output. Used as the IRSA trust principal for the LB Controller role. Required only when install\_lb\_controller = true and lbc\_use\_pod\_identity = false. | `string` | `null` | no |
| <a name="input_oidc_provider_url"></a> [oidc\_provider\_url](#input\_oidc\_provider\_url) | Issuer URL of the OIDC provider (without the https:// prefix). Sourced from the eks-cluster project output. Used in the IRSA sub condition. Required only when install\_lb\_controller = true and lbc\_use\_pod\_identity = false. | `string` | `null` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the workload VPC. Sourced from the workload-vpc project output. Passed to the LB Controller Helm release as vpcId. Required only when install\_lb\_controller = true. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_coredns_addon_arn"></a> [coredns\_addon\_arn](#output\_coredns\_addon\_arn) | ARN of the CoreDNS managed add-on. Null when install\_coredns = false. |
| <a name="output_coredns_addon_version"></a> [coredns\_addon\_version](#output\_coredns\_addon\_version) | Resolved version of the installed CoreDNS managed add-on. Null when install\_coredns = false. |
| <a name="output_lb_controller_role_arn"></a> [lb\_controller\_role\_arn](#output\_lb\_controller\_role\_arn) | ARN of the IRSA role assumed by the LB Controller service account. Null when the controller is not installed or lbc\_use\_pod\_identity = true. |
| <a name="output_lb_controller_role_name"></a> [lb\_controller\_role\_name](#output\_lb\_controller\_role\_name) | Name of the LB Controller IRSA role. Null when the controller is not installed or lbc\_use\_pod\_identity = true. |
<!-- END_TF_DOCS -->