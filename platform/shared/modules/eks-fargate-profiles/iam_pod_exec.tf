data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  pod_execution_role_name = coalesce(var.pod_execution_role_name, "${var.cluster_name}-fargate-pod-exec")
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
    # Confused-deputy guard: restricts which Fargate profiles can assume this
    # role to profiles belonging to this specific cluster in this account.
    # The wildcard on the profile name is intentional — the profile ARNs are
    # not available at role-creation time (circular dependency).
    # Account ID and region are always the deploying identity's — there is no
    # case in this architecture where the role and the cluster live in
    # different accounts or regions.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${var.cluster_name}/*"]
    }
  }
}

resource "aws_iam_role" "pod_exec" {
  name               = local.pod_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.pod_exec_assume.json
}

resource "aws_iam_role_policy_attachment" "pod_exec" {
  role       = aws_iam_role.pod_exec.name
  policy_arn = data.aws_iam_policy.pod_exec.arn
}
