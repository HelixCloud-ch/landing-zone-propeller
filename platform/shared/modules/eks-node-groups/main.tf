# ── Managed Node Groups ────────────────────────────────────────────────────────

resource "aws_eks_node_group" "this" {
  for_each = { for ng in var.node_groups : ng.name => ng }

  cluster_name    = var.cluster_name
  node_group_name = each.value.name
  node_role_arn   = each.value.node_role_arn
  subnet_ids      = each.value.subnet_ids

  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type
  ami_type        = each.value.ami_type
  release_version = each.value.release_version
  disk_size       = each.value.launch_template_id == null ? each.value.disk_size : null

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = each.value.max_unavailable
  }

  dynamic "launch_template" {
    for_each = each.value.launch_template_id != null ? [1] : []
    content {
      id      = each.value.launch_template_id
      version = each.value.launch_template_version
    }
  }

  labels = length(each.value.labels) > 0 ? each.value.labels : null

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size, scaling_config[0].min_size]

    precondition {
      condition = alltrue([
        for t in each.value.instance_types :
        length(data.aws_ec2_instance_type_offerings.validate[t].instance_types) > 0
      ])
      error_message = "Node group \"${each.value.name}\": one or more instance_types are not available in this region."
    }
  }
}
