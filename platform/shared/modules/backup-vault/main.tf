locals {
  create_kms_key = var.kms_key_arn == null
  kms_key_arn    = local.create_kms_key ? module.kms_key[0].key_arn : var.kms_key_arn

  share_with_accounts = length(var.cross_account_access.account_ids) > 0
  share_with_org      = var.cross_account_access.organization_id != null
  create_policy       = local.share_with_accounts || local.share_with_org
}

# Created only when the caller does not bring its own key. Cross-account copy
# needs a customer managed key: AWS managed keys have immutable key policies
# and cannot be shared with the peer account.
module "kms_key_policy" {
  source = "../backup-kms-key-policy"
  count  = local.create_kms_key ? 1 : 0

  cross_account_access = var.cross_account_access
}

module "kms_key" {
  source = "../kms-key"
  count  = local.create_kms_key ? 1 : 0

  description = "AWS Backup vault ${var.name}"
  alias       = coalesce(var.kms_key_alias, "backup/${var.name}")
  policy_json = module.kms_key_policy[0].json
}

resource "aws_backup_vault" "this" {
  name        = var.name
  kms_key_arn = local.kms_key_arn
}

# Only backup:CopyIntoBackupVault is a vault-policy concern;
# CopyFromBackupVault is identity-based and lives on the copying role.
data "aws_iam_policy_document" "access" {
  count = local.create_policy ? 1 : 0

  dynamic "statement" {
    for_each = local.share_with_accounts ? [1] : []
    content {
      sid    = "AllowCopyIntoFromAccounts"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = [for id in var.cross_account_access.account_ids : "arn:aws:iam::${id}:root"]
      }
      actions   = ["backup:CopyIntoBackupVault"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.share_with_org ? [1] : []
    content {
      sid    = "AllowCopyIntoFromOrganization"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      actions   = ["backup:CopyIntoBackupVault"]
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
}

resource "aws_backup_vault_policy" "this" {
  count = local.create_policy ? 1 : 0

  backup_vault_name = aws_backup_vault.this.name
  policy            = data.aws_iam_policy_document.access[0].json
}

# Governance mode only: changeable_for_days is never set, so this module can
# never create an irreversible compliance-mode lock.
resource "aws_backup_vault_lock_configuration" "this" {
  count = var.vault_lock == null ? 0 : 1

  backup_vault_name  = aws_backup_vault.this.name
  min_retention_days = var.vault_lock.min_retention_days
  max_retention_days = var.vault_lock.max_retention_days
}
