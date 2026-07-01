locals {
  ecr_region = coalesce(var.ecr_region, var.region)
}

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
    # checkov:skip=CKV_AWS_111: ecr:GetAuthorizationToken does not support resource-level restrictions (AWS API constraint)
    # checkov:skip=CKV_AWS_356: ecr:GetAuthorizationToken does not support resource-level restrictions (AWS API constraint)
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
  role   = var.pod_execution_role_name
  policy = data.aws_iam_policy_document.ecr_pull.json
}
