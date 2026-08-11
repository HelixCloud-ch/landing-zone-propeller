locals {
  # ── Cluster subnets ─────────────────────────────────────────────────────────
  cluster_subnets = flatten([for t in var.cluster_subnet_tiers : var.subnet_ids_by_tier[t]])

  # ── Fargate ─────────────────────────────────────────────────────────────────

  fargate_tier = coalesce(var.fargate_subnet_tier, var.cluster_subnet_tiers[0])

  create_fargate = length(var.fargate_profiles) > 0

  fargate_profiles_resolved = [
    for p in var.fargate_profiles : {
      name               = p.name
      namespace          = p.namespace
      labels             = p.labels
      subnet_ids         = var.subnet_ids_by_tier[coalesce(p.subnet_tier, local.fargate_tier)]
      pod_execution_role = p.pod_execution_role
    }
  ]

  pod_execution_roles = {
    for k in toset([for p in var.fargate_profiles : p.pod_execution_role if p.pod_execution_role != null]) :
    k => { additional_policy_arns = [] }
  }

  # ── Node groups ─────────────────────────────────────────────────────────────

  create_node_groups = length(var.node_groups) > 0

  # Create the shared role only if at least one node group does not supply its own
  create_node_role = local.create_node_groups && anytrue([for ng in var.node_groups : ng.node_role_arn == null])

  node_groups_resolved = [
    for ng in var.node_groups : {
      name                    = ng.name
      node_role_arn           = coalesce(ng.node_role_arn, local.create_node_role ? aws_iam_role.node[0].arn : null)
      subnet_ids              = var.subnet_ids_by_tier[coalesce(ng.subnet_tier, var.cluster_subnet_tiers[0])]
      instance_types          = ng.instance_types
      capacity_type           = ng.capacity_type
      ami_type                = ng.ami_type
      release_version         = ng.release_version
      disk_size               = ng.disk_size
      desired_size            = ng.desired_size
      min_size                = ng.min_size
      max_size                = ng.max_size
      max_unavailable         = ng.max_unavailable
      labels                  = ng.labels
      taints                  = ng.taints
      launch_template_id      = ng.launch_template_id
      launch_template_version = ng.launch_template_version
    }
  ]

  # ── Access entries ──────────────────────────────────────────────────────────

  additional_admin_arns = toset(concat(
    var.additional_admin_arns,
    [for name in var.additional_admin_role_names : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"]
  ))
}
