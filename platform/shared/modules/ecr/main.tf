# ── Cross-account pull policy ─────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

locals {
  cross_account_pull_policy = length(var.pull_access_org_paths) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrgPull"
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
      ]
      Condition = {
        "ForAnyValue:StringLike" = {
          "aws:PrincipalOrgPaths" = var.pull_access_org_paths
        }
      }
    }]
  }) : null
}

# ── Repository creation templates ─────────────────────────────────────────────
# Defines default settings for repositories auto-created on push, pull-through
# cache, or replication. Each template matches a namespace prefix.

resource "aws_ecr_repository_creation_template" "templates" {
  for_each = var.repository_creation_templates

  prefix               = each.key
  description          = each.value.description
  image_tag_mutability = each.value.image_tag_mutability
  applied_for          = each.value.applied_for
  custom_role_arn      = aws_iam_role.ecr_template.arn

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = each.value.image_tag_mutability_exclusion_filters
    content {
      filter      = image_tag_mutability_exclusion_filter.value.filter
      filter_type = image_tag_mutability_exclusion_filter.value.filter_type
    }
  }

  encryption_configuration {
    encryption_type = each.value.encryption_type
    kms_key         = each.value.kms_key
  }

  repository_policy = coalesce(each.value.repository_policy, local.cross_account_pull_policy)
  lifecycle_policy  = each.value.lifecycle_policy
  resource_tags     = merge(var.default_repository_tags, each.value.resource_tags)
}
