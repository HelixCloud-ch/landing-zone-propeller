# ── Locate the worker node IAM role ───────────────────────────────────────────
# ROSA HCP creates worker roles with a predictable naming convention.
# If the consumer overrides worker_role_name, use that; otherwise derive from
# the cluster name.

locals {
  ecr_region       = coalesce(var.ecr_region, var.region)
  worker_role_name = coalesce(var.worker_role_name, "${var.cluster_name}-account-HCP-ROSA-Worker-Role")
}

# Verify the role exists
data "aws_iam_role" "worker" {
  name = local.worker_role_name
}

# ── ECR pull policy ───────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["arn:aws:ecr:${local.ecr_region}:${var.ecr_account_id}:repository/*"]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "ecr-cross-account-pull"
  role   = data.aws_iam_role.worker.name
  policy = data.aws_iam_policy_document.ecr_pull.json
}
