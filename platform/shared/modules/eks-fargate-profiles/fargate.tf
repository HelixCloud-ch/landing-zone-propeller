resource "aws_eks_fargate_profile" "this" {
  for_each = { for p in var.fargate_profiles : p.name => p }

  cluster_name           = var.cluster_name
  fargate_profile_name   = each.value.name
  pod_execution_role_arn = local.role_arns[coalesce(each.value.pod_execution_role, "default")]
  subnet_ids             = each.value.subnet_ids

  selector {
    namespace = each.value.namespace
    labels    = length(each.value.labels) > 0 ? each.value.labels : null
  }

  lifecycle {
    precondition {
      condition     = contains(keys(local.role_defs), coalesce(each.value.pod_execution_role, "default"))
      error_message = "Profile \"${each.value.name}\" references pod_execution_role \"${each.value.pod_execution_role}\", which is not a key in pod_execution_roles."
    }
  }
}
