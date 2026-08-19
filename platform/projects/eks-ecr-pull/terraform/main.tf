locals {
  ecr_region = coalesce(var.ecr_region, var.region)

  # Merge all role names into a single set for iteration
  role_names = toset(compact(concat(
    var.pod_execution_role_name != null ? [var.pod_execution_role_name] : [],
    var.additional_role_names,
  )))
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
  for_each = local.role_names

  name   = "ecr-cross-account-pull"
  role   = each.value
  policy = data.aws_iam_policy_document.ecr_pull.json
}
