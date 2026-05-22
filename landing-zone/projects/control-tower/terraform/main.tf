locals {
  centralized_logging = {
    accountId = var.log_archive_account_id
    configurations = {
      loggingBucket       = { retentionDays = var.logging_bucket_retention_days }
      accessLoggingBucket = { retentionDays = var.access_logging_bucket_retention_days }
    }
    enabled = true
  }

  backup = merge(
    { enabled = var.enable_backup },
    var.enable_backup ? {
      configurations = {
        backupAdmin   = { accountId = var.backup_admin_account_id }
        centralBackup = { accountId = var.backup_central_account_id }
        kmsKeyArn     = var.backup_kms_key_arn
      }
    } : {}
  )

  manifest = {
    governedRegions    = sort(var.governed_regions)
    centralizedLogging = local.centralized_logging
    config             = { accountId = var.security_tooling_account_id, enabled = true }
    securityRoles      = { accountId = var.security_tooling_account_id, enabled = true }
    accessManagement   = { enabled = var.enable_access_management }
    backup             = local.backup
  }
}

resource "aws_controltower_landing_zone" "this" {
  manifest_json     = jsonencode(local.manifest)
  version           = var.landing_zone_version
  remediation_types = var.enable_inheritance_drift_remediation ? ["INHERITANCE_DRIFT"] : []
}
