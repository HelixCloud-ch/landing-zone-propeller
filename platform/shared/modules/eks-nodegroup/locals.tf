locals {
  node_group_name = coalesce(var.node_group_name, "${var.cluster_name}-nodes")

  # IAM: use module-created role or externally-supplied ARN
  node_role_arn = var.create_node_role ? aws_iam_role.node[0].arn : var.node_role_arn
}
