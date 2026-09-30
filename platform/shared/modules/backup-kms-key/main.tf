data "aws_caller_identity" "current" {}

locals {
  # Cross-account statements follow the AWS Backup key-policy guidance: usage
  # actions for the peer principals, and CreateGrant only when the grant is
  # for an AWS service acting on the peer's behalf (kms:GrantIsForAWSResource).
  usage_actions = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
  ]

  share_with_accounts = length(var.cross_account_access.account_ids) > 0
  share_with_org      = var.cross_account_access.organization_id != null
}

data "aws_iam_policy_document" "this" {
  # checkov:skip=CKV_AWS_109: key policy; "*" resource means this key only, and the kms:* grant is the account-root statement AWS requires to avoid an unmanageable key.
  # checkov:skip=CKV_AWS_111: key policy; write actions are limited to this key, and cross-account statements are scoped by principal, org ID or kms:GrantIsForAWSResource.
  # checkov:skip=CKV_AWS_356: key policy; Resource "*" is the only valid value in a KMS key policy and refers to the key itself.
  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = local.share_with_accounts ? [1] : []
    content {
      sid    = "AllowPeerAccountsUse"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = [for id in var.cross_account_access.account_ids : "arn:aws:iam::${id}:root"]
      }
      actions   = local.usage_actions
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.share_with_accounts ? [1] : []
    content {
      sid    = "AllowPeerAccountsGrantsForAwsServices"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = [for id in var.cross_account_access.account_ids : "arn:aws:iam::${id}:root"]
      }
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.share_with_org ? [1] : []
    content {
      sid    = "AllowOrganizationUse"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions   = local.usage_actions
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [var.cross_account_access.organization_id]
      }
      dynamic "condition" {
        for_each = length(var.cross_account_access.org_paths) > 0 ? [1] : []
        content {
          test     = "ForAnyValue:StringLike"
          variable = "aws:PrincipalOrgPaths"
          values   = var.cross_account_access.org_paths
        }
      }
    }
  }

  dynamic "statement" {
    for_each = local.share_with_org ? [1] : []
    content {
      sid    = "AllowOrganizationGrantsForAwsServices"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [var.cross_account_access.organization_id]
      }
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
      dynamic "condition" {
        for_each = length(var.cross_account_access.org_paths) > 0 ? [1] : []
        content {
          test     = "ForAnyValue:StringLike"
          variable = "aws:PrincipalOrgPaths"
          values   = var.cross_account_access.org_paths
        }
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_rotation
  policy                  = data.aws_iam_policy_document.this.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}
