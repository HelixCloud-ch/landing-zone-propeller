# eks-cluster

Generic Amazon EKS cluster project. Creates the control plane by default;
optionally provisions Fargate profiles (`fargate_profiles`) and/or EC2 managed
node groups (`node_groups`) for single-mode or mixed-mode compute. Supports
sleep/wake via scale-to-zero for node groups.

## Compute modes

The project lets a consumer switch compute mode by changing
`config.auto.tfvars` alone — no hand-deleting resources:

| Mode | How to select | What gets created |
|------|---------------|-------------------|
| Plain EKS | Both lists empty (default) | Control plane, cluster IAM role, OIDC provider |
| EKS on Fargate | `fargate_profiles = [...]` | The above + Fargate profiles + pod execution role(s) |
| EKS on EC2 | `node_groups = [...]` | The above + managed node group(s) + shared node role |
| Mixed | Both lists populated | All of the above |

See `config-fargate.auto.tfvars.example`, `config-nodegroup.auto.tfvars.example`,
and `config-mixed.auto.tfvars.example` for concrete examples.

## Pipeline inputs

`vpc_id` and `subnet_ids_by_tier` are injected by the pipeline from the
`workload-vpc` step outputs — do **not** set them in `config.auto.tfvars`
(the latter arrives pre-parsed as HCL, no `jsondecode` needed). The cluster's
`vpc_config` attaches the subnets from `cluster_subnet_tiers` (one
`vpc_config` block, so all selected tiers flatten into one subnet list —
requires at least two AZs). Fargate profiles use `fargate_subnet_tier`
(defaults to first cluster tier). Node groups use per-group `subnet_tier`
(defaults to first cluster tier).

## Fargate profiles

Each `fargate_profiles` entry maps a namespace (plus optional label
selectors) to a pod execution role. Set `pod_execution_role` to a role key
(e.g. `"test"`/`"prod"`) to give a profile an isolated execution role for
cross-account ECR pull; profiles sharing a key share a role, and omitting it
uses the shared default role. One role is created per distinct key
referenced.

## Sleep/Wake (EC2 node groups)

| Mode | Sleep behaviour | Wake behaviour | Cost while sleeping |
|------|----------------|----------------|---------------------|
| `scale-zero` (default) | Scale all node groups to desired=0, min=0 | Restore previous desired/min/max | ~$0.10/hr (control plane only) |
| `destroy` | Full `terraform destroy` | Full `terraform apply` | $0 |

For Fargate-only clusters, sleep/wake is a no-op (Fargate has no idle cost).

## Node IAM role

When `node_groups` is non-empty and at least one group does not supply a custom
`node_role_arn`, the project creates a shared node role
(`<cluster_name>-eks-node`) and attaches the policies listed in
`node_role_policy_arns`. The default is exactly the two policies required for
a node to boot and join the cluster — `AmazonEKSWorkerNodePolicy` and
`AmazonEC2ContainerRegistryReadOnly` (image pulls for the CNI DaemonSet happen
before any addon-managed IRSA identity exists).

`node_role_policy_arns` **replaces** the attached set, it does not append to
it. To add a policy (e.g. `AmazonSSMManagedInstanceCore` for Session Manager
access, or a cross-account ECR pull policy), override the variable with the
two defaults plus whatever else is needed:

```hcl
node_role_policy_arns = [
  "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
  "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
]
```

If every node group supplies its own `node_role_arn`, the shared role is not
created.

## VPC CNI IRSA role — not here

`AmazonEKS_CNI_Policy` is **not** attached to the node role, and this project
does not create the vpc-cni IRSA role either. Per [AWS's
recommendation](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html),
that role belongs to `eks-addon-vpc-cni`, which owns both the IRSA role
(trusted by the `aws-node` ServiceAccount in `kube-system`) and the vpc-cni
managed add-on itself. Wire `oidc_provider_arn`/`oidc_provider_url` from this
project's outputs into `eks-addon-vpc-cni`.

## API server access

The cluster's API server endpoint is private-only by default
(`endpoint_public_access = false`). Anything outside the cluster's own
security group that needs to reach port 443 — a VPC-attached deploy runner
applying `eks-addons` (helm/kubernetes providers), or operator networks over
TGW/VPN — needs an explicit path in:

- `api_server_ingress_cidrs`: when non-empty, this project creates a security
  group with these CIDRs as ingress rules and attaches it to the cluster.
  Empty (default) creates no security group.
- `additional_security_group_ids`: externally-managed security group IDs to
  attach instead, for when a centralized security-group plane owns SG
  lifecycle. Leave `api_server_ingress_cidrs` empty when using this.

## Operational notes

**EKS version.** Pinned to a specific minor version. Upgrades are manual and
sequential — never skip a minor version.

**OIDC / IRSA.** Created by default, required on Fargate (Pod Identity is not
supported there).

**Secrets encryption.** Off by default. Enable with `secrets_encryption_enabled
= true` + `kms_key_arn`.

## What does NOT belong here

- **Cluster add-ons** (CoreDNS, kube-proxy, LB controller) → `eks-addons` / `eks-addon-lb-controller`
- **VPC CNI and its IRSA role** → `eks-addon-vpc-cni`
- **Cross-account ECR pull** → `eks-ecr-pull`
- **Autoscaler / Karpenter** → `eks-addon-autoscaler` / future `eks-addon-karpenter`
- **Security group rules for centralized SG plane** → future `security-groups` project

## References

- [Amazon EKS — Security group requirements](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)
- [Amazon EKS — Managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/create-managed-node-group.html)
- [Amazon EKS — Getting started with Fargate](https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cluster"></a> [cluster](#module\_cluster) | ../../../shared/modules/eks-cluster | n/a |
| <a name="module_fargate_profiles"></a> [fargate\_profiles](#module\_fargate\_profiles) | ../../../shared/modules/eks-fargate-profiles | n/a |
| <a name="module_node_groups"></a> [node\_groups](#module\_node\_groups) | ../../../shared/modules/eks-node-groups | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_access_entry.additional_admins](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.additional_admins](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.api_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.api_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_admin_arns"></a> [additional\_admin\_arns](#input\_additional\_admin\_arns) | IAM principal ARNs to grant AmazonEKSClusterAdmin access via EKS access entries. Use this for VPC-attached deploy runners or other roles that need full cluster access but didn't create the cluster. | `list(string)` | `[]` | no |
| <a name="input_additional_admin_role_names"></a> [additional\_admin\_role\_names](#input\_additional\_admin\_role\_names) | IAM role names (in the same account) to grant AmazonEKSClusterAdmin access. Resolved to full ARNs automatically. | `list(string)` | `[]` | no |
| <a name="input_additional_security_group_ids"></a> [additional\_security\_group\_ids](#input\_additional\_security\_group\_ids) | Externally-managed security group IDs attached to the cluster's cross-account ENIs. See README ('API server access'). | `list(string)` | `[]` | no |
| <a name="input_api_server_ingress_cidrs"></a> [api\_server\_ingress\_cidrs](#input\_api\_server\_ingress\_cidrs) | CIDR blocks allowed to reach the private API server on TCP 443. Empty (default) creates no security group. See README ('API server access'). | `list(string)` | `[]` | no |
| <a name="input_authentication_mode"></a> [authentication\_mode](#input\_authentication\_mode) | EKS access-config authentication mode: API (recommended), CONFIG\_MAP, or API\_AND\_CONFIG\_MAP. | `string` | `"API"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster. Supplied per consumer in config.auto.tfvars. | `string` | n/a | yes |
| <a name="input_cluster_subnet_tiers"></a> [cluster\_subnet\_tiers](#input\_cluster\_subnet\_tiers) | Keys in subnet\_ids\_by\_tier attached to the cluster's vpc\_config. Requires at least two AZs. See README ('Pipeline inputs'). | `list(string)` | n/a | yes |
| <a name="input_consumer_tags"></a> [consumer\_tags](#input\_consumer\_tags) | Consumer-specific tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_eks_version"></a> [eks\_version](#input\_eks\_version) | Pinned Kubernetes minor version for the cluster (e.g. "1.30"). Must be updated explicitly; no automatic upgrades. | `string` | n/a | yes |
| <a name="input_enabled_cluster_log_types"></a> [enabled\_cluster\_log\_types](#input\_enabled\_cluster\_log\_types) | Control-plane log types forwarded to CloudWatch. Defaults to all five per AWS best practice. | `list(string)` | <pre>[<br/>  "api",<br/>  "audit",<br/>  "authenticator",<br/>  "controllerManager",<br/>  "scheduler"<br/>]</pre> | no |
| <a name="input_fargate_profiles"></a> [fargate\_profiles](#input\_fargate\_profiles) | Fargate profiles to create. Empty (default) creates none. See README ('Fargate profiles') for the pod\_execution\_role sharing model. | <pre>list(object({<br/>    name               = string<br/>    namespace          = string<br/>    labels             = optional(map(string), {})<br/>    subnet_tier        = optional(string)<br/>    pod_execution_role = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_fargate_subnet_tier"></a> [fargate\_subnet\_tier](#input\_fargate\_subnet\_tier) | Key in subnet\_ids\_by\_tier used to place Fargate profiles. Defaults to the first entry of cluster\_subnet\_tiers when null. Ignored when fargate\_profiles is empty. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the symmetric CMK used to encrypt Kubernetes secrets. Required when secrets\_encryption\_enabled is true; ignored otherwise. | `string` | `null` | no |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | Managed node groups to create. Each shares the default node role unless node\_role\_arn is set. Empty (default) creates none. | <pre>list(object({<br/>    name            = string<br/>    subnet_tier     = optional(string)<br/>    instance_types  = optional(list(string), ["t3.medium"])<br/>    capacity_type   = optional(string, "ON_DEMAND")<br/>    ami_type        = optional(string, "AL2023_x86_64_STANDARD")<br/>    release_version = optional(string)<br/>    disk_size       = optional(number)<br/>    desired_size    = optional(number, 2)<br/>    min_size        = optional(number, 1)<br/>    max_size        = optional(number, 10)<br/>    max_unavailable = optional(number, 1)<br/>    labels          = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = optional(string)<br/>      effect = string<br/>    })), [])<br/>    node_role_arn           = optional(string)<br/>    launch_template_id      = optional(string)<br/>    launch_template_version = optional(string, "$Latest")<br/>  }))</pre> | `[]` | no |
| <a name="input_node_role_policy_arns"></a> [node\_role\_policy\_arns](#input\_node\_role\_policy\_arns) | IAM policy ARNs on the shared node role. Replaces the whole set, does not append. See README ('Node IAM role'). | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",<br/>  "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"<br/>]</pre> | no |
| <a name="input_propeller_tags"></a> [propeller\_tags](#input\_propeller\_tags) | Propeller framework tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the EKS cluster is deployed. | `string` | n/a | yes |
| <a name="input_secrets_encryption_enabled"></a> [secrets\_encryption\_enabled](#input\_secrets\_encryption\_enabled) | When true, enables CMK envelope encryption for Kubernetes secrets using kms\_key\_arn. | `bool` | `false` | no |
| <a name="input_subnet_ids_by_tier"></a> [subnet\_ids\_by\_tier](#input\_subnet\_ids\_by\_tier) | Map of tier name to ordered subnet ID list, from workload-vpc.subnet\_ids\_by\_tier. See README ('Pipeline inputs'). | `map(list(string))` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Base tags merged into the provider default\_tags block. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the workload VPC. Sourced from the workload-vpc project output. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api_ingress_security_group_id"></a> [api\_ingress\_security\_group\_id](#output\_api\_ingress\_security\_group\_id) | ID of the project-created API server ingress security group. Null when api\_server\_ingress\_cidrs is empty. |
| <a name="output_autoscaling_group_names"></a> [autoscaling\_group\_names](#output\_autoscaling\_group\_names) | Map of node group key to list of ASG names. Null when no node groups are configured. |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64-encoded certificate authority data for the cluster. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | Private API server endpoint URL for the EKS cluster. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the EKS cluster. |
| <a name="output_cluster_security_group_id"></a> [cluster\_security\_group\_id](#output\_cluster\_security\_group\_id) | ID of the EKS-managed cluster security group. |
| <a name="output_node_group_names"></a> [node\_group\_names](#output\_node\_group\_names) | Map of node group key to node group name. Null when no node groups are configured. |
| <a name="output_node_role_arn"></a> [node\_role\_arn](#output\_node\_role\_arn) | ARN of the shared node IAM role. Null when no node groups are configured or all groups supply their own role. |
| <a name="output_node_role_name"></a> [node\_role\_name](#output\_node\_role\_name) | Name of the shared node IAM role. Null when no node groups are configured or all groups supply their own role. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the IAM OIDC identity provider associated with the cluster. |
| <a name="output_oidc_provider_url"></a> [oidc\_provider\_url](#output\_oidc\_provider\_url) | Issuer URL of the OIDC provider (without the https:// prefix). |
| <a name="output_pod_execution_role_arn"></a> [pod\_execution\_role\_arn](#output\_pod\_execution\_role\_arn) | ARN of the default pod execution IAM role. Null when no Fargate profiles are configured. |
| <a name="output_pod_execution_role_arns"></a> [pod\_execution\_role\_arns](#output\_pod\_execution\_role\_arns) | Map of role key to pod execution IAM role ARN. Null when no Fargate profiles are configured. |
| <a name="output_pod_execution_role_name"></a> [pod\_execution\_role\_name](#output\_pod\_execution\_role\_name) | Name of the default pod execution IAM role. Null when no Fargate profiles are configured. |
| <a name="output_pod_execution_role_names"></a> [pod\_execution\_role\_names](#output\_pod\_execution\_role\_names) | Map of role key to pod execution IAM role name. Wire the relevant key into eks-ecr-pull. Null when no Fargate profiles are configured. |
<!-- END_TF_DOCS -->
