# ── Repository creation templates ─────────────────────────────────────────────
# Defines default settings for repositories auto-created on push, pull-through
# cache, or replication. Each template matches a namespace prefix.

resource "aws_ecr_repository_creation_template" "templates" {
  for_each = var.repository_creation_templates

  prefix               = each.key
  description          = each.value.description
  image_tag_mutability = each.value.image_tag_mutability
  applied_for          = each.value.applied_for
  custom_role_arn      = each.value.custom_role_arn

  encryption_configuration {
    encryption_type = each.value.encryption_type
    kms_key         = each.value.kms_key
  }

  repository_policy = each.value.repository_policy
  lifecycle_policy  = each.value.lifecycle_policy
  resource_tags     = merge(var.default_repository_tags, each.value.resource_tags)
}

# ── Cross-account access (organization-wide) ─────────────────────────────────
# Registry-level policy granting pull access to accounts in specified OUs or
# the entire organization. This applies to all repositories in the registry.

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "registry_policy" {
  count = var.create_registry_policy ? 1 : 0

  statement {
    sid    = "AllowCrossAccountPull"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]

    condition {
      test     = "StringLike"
      variable = "aws:PrincipalOrgPaths"
      values   = var.pull_access_org_paths
    }
  }
}

resource "aws_ecr_registry_policy" "this" {
  count  = var.create_registry_policy ? 1 : 0
  policy = data.aws_iam_policy_document.registry_policy[0].json
}
