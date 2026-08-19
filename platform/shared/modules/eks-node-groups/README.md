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
| [aws_ec2_instance_type_offerings.validate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_instance_type_offerings) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster this node group belongs to. | `string` | n/a | yes |
| <a name="input_node_groups"></a> [node\_groups](#input\_node\_groups) | List of managed node groups to create. Each entry produces one aws\_eks\_node\_group with its own scaling config, instance types, and labels/taints. The node\_role\_arn and subnet\_ids are resolved by the calling project. | <pre>list(object({<br/>    name            = string<br/>    node_role_arn   = string<br/>    subnet_ids      = list(string)<br/>    instance_types  = optional(list(string), ["t3.medium"])<br/>    capacity_type   = optional(string, "ON_DEMAND")<br/>    ami_type        = optional(string, "AL2023_x86_64_STANDARD")<br/>    release_version = optional(string)<br/>    disk_size       = optional(number)<br/>    desired_size    = optional(number, 2)<br/>    min_size        = optional(number, 1)<br/>    max_size        = optional(number, 10)<br/>    max_unavailable = optional(number, 1)<br/>    labels          = optional(map(string), {})<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = optional(string)<br/>      effect = string<br/>    })), [])<br/>    launch_template_id      = optional(string)<br/>    launch_template_version = optional(string, "$Latest")<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_autoscaling_group_names"></a> [autoscaling\_group\_names](#output\_autoscaling\_group\_names) | Map of node group key to list of ASG names. |
| <a name="output_node_group_arns"></a> [node\_group\_arns](#output\_node\_group\_arns) | Map of node group key to node group ARN. |
| <a name="output_node_group_names"></a> [node\_group\_names](#output\_node\_group\_names) | Map of node group key to node group name. |
<!-- END_TF_DOCS -->
