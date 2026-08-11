output "node_group_name" {
  description = "Name of the EKS managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "ARN of the EKS managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "Status of the EKS managed node group."
  value       = aws_eks_node_group.this.status
}

output "node_role_arn" {
  description = "ARN of the node IAM role."
  value       = local.node_role_arn
}

output "node_role_name" {
  description = "Name of the node IAM role. Null when create_node_role is false."
  value       = var.create_node_role ? aws_iam_role.node[0].name : null
}

output "autoscaling_group_names" {
  description = "Names of the autoscaling groups backing the node group. Useful for autoscaler IAM policies."
  value       = [for r in aws_eks_node_group.this.resources : [for asg in r.autoscaling_groups : asg.name]][0]
}
