# eks-nodegroup

Creates an EKS managed node group (EC2-backed) for an existing EKS cluster.

## What this module creates

- **Managed node group** (`aws_eks_node_group`) with configurable instance
  types, scaling, and update strategy.
- **Launch template** with IMDSv2 enforcement, encrypted root volume, and
  instance Name tags. Can be disabled in favour of an externally-managed
  template.
- **Node IAM role** with AmazonEKSWorkerNodePolicy (always attached) plus
  configurable default policies (ECR read, VPC CNI, SSM). Can be disabled in
  favour of an externally-managed role.

## What this module does NOT own

- **Security groups** — managed by the calling project (e.g. the eks-cluster
  project owns all SG lifecycle). Pass IDs via `security_group_ids`.
- **Cluster control plane** — this module only references the cluster by name.

## Usage

```hcl
module "nodegroup" {
  source = "../../../shared/modules/eks-nodegroup"

  cluster_name = module.cluster.cluster_name
  subnet_ids   = var.subnet_ids

  instance_types = ["m7i-flex.large", "m6i.large"]
  desired_size   = 3
  min_size       = 2
  max_size       = 10
}
```

## Design decisions

- **Single node group per module instance.** To create multiple node groups
  (system pool + workload pool), instantiate this module multiple times with
  `for_each`.
- **`desired_size` ignored after creation.** The `ignore_changes` lifecycle rule
  prevents Terraform from overriding autoscaler decisions.
- **AMI type defaults to AL2023.** Amazon Linux 2023 is the current EKS
  recommendation over AL2.
- **IMDSv2 required by default** (hop limit 2 for containers). This aligns with
  AWS security best practices.
- **No security group management.** EKS automatically attaches the cluster
  security group to managed node group instances. Supplementary SGs are the
  caller's responsibility (passed via `security_group_ids`).
  See: [EKS security group requirements](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_node_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_default_policies](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_ec2_instance_type_offerings.validate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type_offerings) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_node_policy_arns"></a> [additional\_node\_policy\_arns](#input\_additional\_node\_policy\_arns) | Additional IAM policy ARNs to attach to the node role (e.g. cross-account ECR pull, custom application policies). Only used when create\_node\_role is true. | `list(string)` | `[]` | no |
| <a name="input_ami_type"></a> [ami\_type](#input\_ami\_type) | AMI type for the node group. AL2023\_x86\_64\_STANDARD is the current default for EKS-optimized Amazon Linux 2023. | `string` | `"AL2023_x86_64_STANDARD"` | no |
| <a name="input_capacity_type"></a> [capacity\_type](#input\_capacity\_type) | Capacity type: ON\_DEMAND, SPOT, or CAPACITY\_BLOCK. | `string` | `"ON_DEMAND"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster this node group belongs to. | `string` | n/a | yes |
| <a name="input_create_node_role"></a> [create\_node\_role](#input\_create\_node\_role) | Create the node IAM role. Set false to supply an externally-managed role via node\_role\_arn. | `bool` | `true` | no |
| <a name="input_default_node_policy_arns"></a> [default\_node\_policy\_arns](#input\_default\_node\_policy\_arns) | Managed policy ARNs attached to the node role by default (in addition to the<br/>always-attached AmazonEKSWorkerNodePolicy). The default set enables nodes to<br/>boot, pull images, and be reachable via SSM. Override to an empty list if you<br/>prefer delegating these policies to addon projects (eks-addons for VPC CNI,<br/>eks-ecr-pull for ECR, etc.) — but note that nodes need ECR read and CNI<br/>permissions at boot time before any addon project runs. | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",<br/>  "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",<br/>  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"<br/>]</pre> | no |
| <a name="input_desired_size"></a> [desired\_size](#input\_desired\_size) | Desired number of worker nodes. Ignored after initial creation when the autoscaler manages scaling. | `number` | `2` | no |
| <a name="input_disk_size"></a> [disk\_size](#input\_disk\_size) | Root EBS volume size in GiB. When null, EKS uses its default (20 GiB Linux, 50 GiB Windows). Ignored when a launch template is provided. | `number` | `null` | no |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | Ordered list of EC2 instance types for the node group. EKS selects the first type with available capacity. The AWS default is t3.medium. Validated at plan time via data source (fails if a type is not available in this region). | `list(string)` | <pre>[<br/>  "t3.medium"<br/>]</pre> | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Kubernetes labels applied to all nodes in this group. | `map(string)` | `{}` | no |
| <a name="input_launch_template_id"></a> [launch\_template\_id](#input\_launch\_template\_id) | ID of an externally-managed launch template. When null (default), no launch template is used and EKS applies its own defaults (AL2023 AMI, IMDSv2, gp3 root volume). | `string` | `null` | no |
| <a name="input_launch_template_version"></a> [launch\_template\_version](#input\_launch\_template\_version) | Version of the launch template to use. Only relevant when launch\_template\_id is set. Defaults to '$Latest'. | `string` | `"$Latest"` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Maximum number of worker nodes. | `number` | `10` | no |
| <a name="input_max_unavailable"></a> [max\_unavailable](#input\_max\_unavailable) | Maximum number of nodes unavailable during a rolling update. | `number` | `1` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Minimum number of worker nodes. | `number` | `1` | no |
| <a name="input_node_group_name"></a> [node\_group\_name](#input\_node\_group\_name) | Name of the managed node group. Defaults to '<cluster\_name>-nodes' if null. | `string` | `null` | no |
| <a name="input_node_role_arn"></a> [node\_role\_arn](#input\_node\_role\_arn) | ARN of an externally-managed node IAM role. Required when create\_node\_role is false; ignored otherwise. | `string` | `null` | no |
| <a name="input_release_version"></a> [release\_version](#input\_release\_version) | AMI release version for the node group (e.g. '1.30.0-20240625'). When null, EKS uses the latest recommended version for the cluster's Kubernetes version. | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs where worker nodes are launched (private subnets, spanning at least two AZs for high availability). | `list(string)` | n/a | yes |
| <a name="input_taints"></a> [taints](#input\_taints) | Kubernetes taints applied to all nodes in this group. Effect must be NO\_SCHEDULE, NO\_EXECUTE, or PREFER\_NO\_SCHEDULE. | <pre>list(object({<br/>    key    = string<br/>    value  = optional(string)<br/>    effect = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_autoscaling_group_names"></a> [autoscaling\_group\_names](#output\_autoscaling\_group\_names) | Names of the autoscaling groups backing the node group. Useful for autoscaler IAM policies. |
| <a name="output_node_group_arn"></a> [node\_group\_arn](#output\_node\_group\_arn) | ARN of the EKS managed node group. |
| <a name="output_node_group_name"></a> [node\_group\_name](#output\_node\_group\_name) | Name of the EKS managed node group. |
| <a name="output_node_group_status"></a> [node\_group\_status](#output\_node\_group\_status) | Status of the EKS managed node group. |
| <a name="output_node_role_arn"></a> [node\_role\_arn](#output\_node\_role\_arn) | ARN of the node IAM role. |
| <a name="output_node_role_name"></a> [node\_role\_name](#output\_node\_role\_name) | Name of the node IAM role. Null when create\_node\_role is false. |
<!-- END_TF_DOCS -->
