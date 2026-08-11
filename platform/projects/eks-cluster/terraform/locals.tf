locals {
  # ── Cluster subnets ─────────────────────────────────────────────────────────
  # aws_eks_cluster takes a single vpc_config block, so all selected cluster
  # tiers are flattened into one subnet_ids list for the control-plane ENIs.
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

  node_group_subnet_tier = coalesce(var.node_group_subnet_tier, var.cluster_subnet_tiers[0])

  node_groups_resolved = {
    for ng in var.node_groups : ng.name => merge(ng, {
      subnet_ids = var.subnet_ids_by_tier[coalesce(ng.subnet_tier, local.node_group_subnet_tier)]
    })
  }

  # ── Access entries ──────────────────────────────────────────────────────────

  additional_admin_arns = toset(concat(
    var.additional_admin_arns,
    [for name in var.additional_admin_role_names : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"]
  ))
}
