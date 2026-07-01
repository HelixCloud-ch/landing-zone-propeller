data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Always provide a "default" role; merge in any named roles. A caller may
  # override "default" (e.g. to externalize it) by supplying that key.
  role_defs = merge(
    { default = { arn = null, additional_policy_arns = [] } },
    var.pod_execution_roles,
  )

  # Keys this module creates (no external arn supplied).
  managed_role_keys = toset([for k, v in local.role_defs : k if v.arn == null])

  # The default role honors pod_execution_role_name; named roles append the key.
  role_names = {
    for k in local.managed_role_keys : k => (
      k == "default"
      ? coalesce(var.pod_execution_role_name, "${var.cluster_name}-fargate-pod-exec")
      : "${var.cluster_name}-fargate-pod-exec-${k}"
    )
  }

  # Effective ARN per role key: the external arn when supplied, otherwise the
  # ARN of the role this module created.
  role_arns = {
    for k, v in local.role_defs : k => (
      v.arn != null ? v.arn : aws_iam_role.pod_exec[k].arn
    )
  }

  # Flatten (managed role, additional policy ARN) pairs into a single map. The
  # variable validation guarantees external roles carry no additional policies.
  role_additional_policies = merge([
    for k in local.managed_role_keys : {
      for arn in local.role_defs[k].additional_policy_arns : "${k}:${arn}" => { role = k, policy_arn = arn }
    }
  ]...)
}

data "aws_iam_policy" "pod_exec" {
  name = "AmazonEKSFargatePodExecutionRolePolicy"
}

data "aws_iam_policy_document" "pod_exec_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
    # Confused-deputy guard: restricts which Fargate profiles can assume the
    # role to profiles belonging to this cluster in this account. The wildcard
    # on the profile name is intentional — profile ARNs are not available at
    # role-creation time (circular dependency). Account ID and region are
    # always the deploying identity's; there is no cross-account/region case.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${var.cluster_name}/*"]
    }
  }
}

resource "aws_iam_role" "pod_exec" {
  for_each = local.managed_role_keys

  name               = local.role_names[each.value]
  assume_role_policy = data.aws_iam_policy_document.pod_exec_assume.json
}

resource "aws_iam_role_policy_attachment" "pod_exec_base" {
  for_each = local.managed_role_keys

  role       = aws_iam_role.pod_exec[each.value].name
  policy_arn = data.aws_iam_policy.pod_exec.arn
}

resource "aws_iam_role_policy_attachment" "pod_exec_additional" {
  for_each = local.role_additional_policies

  role       = aws_iam_role.pod_exec[each.value.role].name
  policy_arn = each.value.policy_arn
}
