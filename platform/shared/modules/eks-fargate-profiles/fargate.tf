resource "aws_eks_fargate_profile" "this" {
  for_each = { for p in var.fargate_profiles : p.name => p }

  cluster_name           = var.cluster_name
  fargate_profile_name   = each.value.name
  pod_execution_role_arn = aws_iam_role.pod_exec.arn
  subnet_ids             = var.subnet_ids

  selector {
    namespace = each.value.namespace
    labels    = length(each.value.labels) > 0 ? each.value.labels : null
  }
}
