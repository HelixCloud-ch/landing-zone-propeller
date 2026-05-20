locals {
  organization_structure = merge(
    { security = { name = var.security_ou_name } },
    var.sandbox_ou_name != "" ? { sandbox = { name = var.sandbox_ou_name } } : {}
  )

  centralized_logging = {
    accountId = var.log_archive_account_id
    configurations = {
      loggingBucket       = { retentionDays = var.logging_bucket_retention_days }
      accessLoggingBucket = { retentionDays = var.access_logging_bucket_retention_days }
    }
    enabled = true
  }

  backup = var.enable_backup ? {
    enabled = true
    configurations = {
      backupAdmin   = { accountId = var.backup_admin_account_id }
      centralBackup = { accountId = var.backup_central_account_id }
      kmsKeyArn     = var.backup_kms_key_arn
    }
  } : { enabled = false }

  manifest = {
    governedRegions       = var.governed_regions
    organizationStructure = local.organization_structure
    centralizedLogging    = local.centralized_logging
    securityRoles         = { accountId = var.security_tooling_account_id }
    accessManagement      = { enabled = var.enable_access_management }
    backup                = local.backup
  }
}

resource "aws_controltower_landing_zone" "this" {
  manifest_json     = jsonencode(local.manifest)
  version           = var.landing_zone_version
  remediation_types = var.enable_inheritance_drift_remediation ? ["INHERITANCE_DRIFT"] : []
  tags              = var.tags
}
