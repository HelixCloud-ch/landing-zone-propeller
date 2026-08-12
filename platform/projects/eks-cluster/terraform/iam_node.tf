# Shared node IAM role — created only when at least one node group does not
# supply its own node_role_arn.

resource "aws_iam_role" "node" {
  count = local.create_node_role ? 1 : 0

  name = "${var.cluster_name}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.create_node_role ? toset(var.node_role_policy_arns) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}
