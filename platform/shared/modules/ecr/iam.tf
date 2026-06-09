# ── IAM role for repository creation templates ────────────────────────────────
# Required when templates use resource_tags or KMS encryption. ECR assumes this
# role to apply tags/encryption when auto-creating repositories.

data "aws_iam_policy_document" "ecr_template_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecr.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "ecr_template_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:ReplicateImage",
      "ecr:TagResource",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.enable_kms_permissions ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:CreateGrant",
        "kms:RetireGrant",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role" "ecr_template" {
  name               = var.template_role_name
  assume_role_policy = data.aws_iam_policy_document.ecr_template_trust.json
}

resource "aws_iam_role_policy" "ecr_template" {
  name   = "ecr-repository-creation"
  role   = aws_iam_role.ecr_template.id
  policy = data.aws_iam_policy_document.ecr_template_permissions.json
}
