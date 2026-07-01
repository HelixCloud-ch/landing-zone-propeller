# eks-cluster

Generic Amazon EKS cluster project. By default it creates only the control
plane; setting `fargate_profiles` also provisions Fargate. It is a thin
pipeline wrapper around the `eks-cluster` and `eks-fargate-profiles` shared
modules — all resource logic lives in those modules.

## Compute modes

The project is designed so a consumer can move between compute modes by
changing `config.auto.tfvars` alone, without hand-deleting resources:

| Mode | How to select | What gets created |
|------|---------------|-------------------|
| Plain EKS | `fargate_profiles = []` (default) | Control plane, cluster IAM role, OIDC provider |
| EKS on Fargate | `fargate_profiles = [...]` | The above plus Fargate profiles and the pod execution role |

Only these two modes are implemented today. **Node group support, mixed mode
(Fargate + EC2 in the same cluster), and EKS Pod Identity will be implemented
in a later iteration.** Until confirmed-destroy support exists in the pipeline,
switch modes carefully: removing entries can trigger resource deletion on the
next apply.

## Pipeline inputs

`vpc_id` and `subnet_ids_by_tier` are injected by the pipeline from the
`workload-vpc` step outputs — do **not** set them in `config.auto.tfvars`. The
cluster's `vpc_config` attaches the subnets from `cluster_subnet_tiers` (one or
more tiers, flattened into a single list because `aws_eks_cluster` allows a
single `vpc_config` block). Fargate profiles use `fargate_subnet_tier`, which
defaults to the first cluster tier. Future node groups will get their own tier
selector.

## Operational notes

**EKS version (`eks_version`).** Pinned to a specific minor version in
`config.auto.tfvars`. Upgrades are manual — bump the value, then apply. Never
skip a minor version; EKS supports only sequential upgrades. Follow the
[EKS upgrade runbook](../../../../notes/wiki/operations/eks-upgrade-runbook.md)
and update add-on versions in lockstep.

**OIDC / IRSA.** The OIDC provider is created by default and is required on
Fargate, because EKS Pod Identity is not supported on Fargate. IRSA is the
only mechanism to grant IAM permissions to Fargate pods.

**Secrets encryption (`secrets_encryption_enabled`).** Defaults to `false`.
Setting it to `true` requires a symmetric CMK in the cluster region; supply
its ARN in `kms_key_arn`. Enabling encryption after cluster creation
re-encrypts existing secrets in place.

**Fargate + CoreDNS.** On a pure-Fargate cluster, include a `kube-system`
profile scoped to `k8s-app=kube-dns` so CoreDNS can schedule. After the first
apply, apply `eks-addons-1` (which installs the CoreDNS managed add-on on
Fargate), then trigger a rollout:

```bash
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status  deployment/coredns -n kube-system
```

## What does NOT belong here

This project contains only the module calls, provider configuration, and the
state backend. Resource implementations and IAM logic belong in the
`eks-cluster` / `eks-fargate-profiles` shared modules. Cluster add-ons (CoreDNS,
the AWS Load Balancer Controller) belong in `eks-addons-1`. Cross-account ECR
pull policy belongs in `eks-ecr-pull`.

## References

- [Amazon EKS User Guide — Getting started with Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html)
- [Amazon EKS User Guide — Secrets envelope encryption](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- [EKS Pod Identity (not supported on Fargate)](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Terraform Registry — aws_eks_cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cluster"></a> [cluster](#module\_cluster) | ../../../shared/modules/eks-cluster | n/a |
| <a name="module_fargate_profiles"></a> [fargate\_profiles](#module\_fargate\_profiles) | ../../../shared/modules/eks-fargate-profiles | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | EKS access-config authentication mode: API (recommended), CONFIG\_MAP, or API\_AND\_CONFIG\_MAP. | `string` | `"API"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Supplied per consumer in config.auto.tfvars. | `string` | n/a | yes |
| <a name="input_cluster_subnet_tiers"></a> [cluster\_subnet\_tiers](#input\_cluster\_subnet\_tiers) | One or more keys in subnet\_ids\_by\_tier whose subnets are attached to the cluster's vpc\_config (control-plane cross-account ENIs). aws\_eks\_cluster allows a single vpc\_config block, so all selected tiers are flattened into one subnet\_ids list. Requires subnets spanning at least two AZs. | `list(string)` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_eks_version"></a> [eks\_version](#input\_eks\_version) | Pinned Kubernetes minor version for the cluster (e.g. "1.30"). Must be updated explicitly; no automatic upgrades. | `string` | n/a | yes |
| <a name="input_enabled_cluster_log_types"></a> [enabled\_cluster\_log\_types](#input\_enabled\_cluster\_log\_types) | Control-plane log types forwarded to CloudWatch. Defaults to all five per AWS best practice. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_fargate_profiles"></a> [fargate\_profiles](#input\_fargate\_profiles) | Fargate profiles to create. Each entry maps a profile name to a namespace selector and optional label selectors. Set subnet\_tier to place a profile in a specific tier of subnet\_ids\_by\_tier (defaults to fargate\_subnet\_tier). Set pod\_execution\_role to a role key so the profile assumes a dedicated pod execution role (e.g. "test"/"prod" for isolated cross-account ECR pull); profiles sharing a role use the same key, and omitting it uses the shared default role. A role is created for each distinct key referenced. When the list is empty, no Fargate profiles or pod execution roles are created (plain EKS cluster). | <pre>list(object({<br/>    name               = string<br/>    namespace          = string<br/>    labels             = optional(map(string), {})<br/>    subnet_tier        = optional(string)<br/>    pod_execution_role = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_fargate_subnet_tier"></a> [fargate\_subnet\_tier](#input\_fargate\_subnet\_tier) | Key in subnet\_ids\_by\_tier used to place Fargate profiles. Defaults to the first entry of cluster\_subnet\_tiers when null. Ignored when fargate\_profiles is empty. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the symmetric CMK used to encrypt Kubernetes secrets. Required when secrets\_encryption\_enabled is true; ignored otherwise. | `string` | `null` | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_secrets_encryption_enabled"></a> [secrets\_encryption\_enabled](#input\_secrets\_encryption\_enabled) | When true, enables CMK envelope encryption for Kubernetes secrets using kms\_key\_arn. | `bool` | `false` | no |
| <a name="input_subnet_ids_by_tier"></a> [subnet\_ids\_by\_tier](#input\_subnet\_ids\_by\_tier) | Map of tier name to ordered subnet ID list, from workload-vpc.subnet\_ids\_by\_tier. Terraform parses the value as HCL when receiving it via -var, so no jsondecode is needed. | `map(list(string))` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the workload VPC. Sourced from the workload-vpc project output. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64-encoded certificate authority data for the cluster. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Private API server endpoint URL for the EKS cluster. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | ID of the EKS-managed cluster security group. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the IAM OIDC identity provider associated with the cluster. |
| <a name="output_oidc_provider_url"></a> [oidc\_provider\_url](#output\_oidc\_provider\_url) | Issuer URL of the OIDC provider (without the https:// prefix). |
| <a name="output_pod_execution_role_arn"></a> [pod\_execution\_role\_arn](#output\_pod\_execution\_role\_arn) | ARN of the default pod execution IAM role. Null when no Fargate profiles are configured. |
| <a name="output_pod_execution_role_arns"></a> [pod\_execution\_role\_arns](#output\_pod\_execution\_role\_arns) | Map of role key to pod execution IAM role ARN. Null when no Fargate profiles are configured. |
| <a name="output_pod_execution_role_name"></a> [pod\_execution\_role\_name](#output\_pod\_execution\_role\_name) | Name of the default pod execution IAM role. Null when no Fargate profiles are configured. |
| <a name="output_pod_execution_role_names"></a> [pod\_execution\_role\_names](#output\_pod\_execution\_role\_names) | Map of role key to pod execution IAM role name. Wire the relevant key into eks-ecr-pull. Null when no Fargate profiles are configured. |
<!-- END_TF_DOCS -->
