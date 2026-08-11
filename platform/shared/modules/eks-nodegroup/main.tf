# ── Managed Node Group ─────────────────────────────────────────────────────────

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = local.node_group_name
  node_role_arn   = local.node_role_arn
  subnet_ids      = var.subnet_ids

  instance_types  = var.instance_types
  capacity_type   = var.capacity_type
  ami_type        = var.ami_type
  release_version = var.release_version
  disk_size       = var.disk_size

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = var.max_unavailable
  }

  dynamic "launch_template" {
    for_each = var.launch_template_id != null ? [1] : []
    content {
      id      = var.launch_template_id
      version = var.launch_template_version
    }
  }

  labels = length(var.labels) > 0 ? var.labels : null

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_default_policies,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]

    precondition {
      condition     = length(data.aws_ec2_instance_type_offerings.validate.instance_types) == length(var.instance_types)
      error_message = "One or more instance_types are not available in this region. Requested: ${join(", ", var.instance_types)}. Available: ${join(", ", data.aws_ec2_instance_type_offerings.validate.instance_types)}."
    }
  }
}

# ── Node IAM Role ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "node" {
  count = var.create_node_role ? 1 : 0

  name = "${local.node_group_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  count = var.create_node_role ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_default_policies" {
  for_each = var.create_node_role ? toset(var.default_node_policy_arns) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "node_additional" {
  for_each = var.create_node_role ? toset(var.additional_node_policy_arns) : toset([])

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}
