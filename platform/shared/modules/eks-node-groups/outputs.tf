output "node_group_names" {
  description = "Map of node group key to node group name."
  value       = { for k, v in aws_eks_node_group.this : k => v.node_group_name }
}

output "node_group_arns" {
  description = "Map of node group key to node group ARN."
  value       = { for k, v in aws_eks_node_group.this : k => v.arn }
}

output "autoscaling_group_names" {
  description = "Map of node group key to list of ASG names."
  value = {
    for k, v in aws_eks_node_group.this :
    k => [for r in v.resources : [for asg in r.autoscaling_groups : asg.name]][0]
  }
}
