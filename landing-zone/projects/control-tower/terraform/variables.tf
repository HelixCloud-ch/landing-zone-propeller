variable "region" {
  type        = string
  description = "AWS region where Control Tower will be deployed (must match Identity Center region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "landing_zone_version" {
  type        = string
  description = "Control Tower landing zone version."
  default     = "4.0"

  validation {
    condition     = var.landing_zone_version == "4.0"
    error_message = "Only landing zone version \"4.0\" is supported."
  }
}

variable "enable_inheritance_drift_remediation" {
  type        = bool
  description = "Whether CT automatically remediates inheritance drift on the landing zone."
  default     = true
}

# ── Governed regions ─────────────────────────────────────────────────────────

variable "governed_regions" {
  type        = list(string)
  description = "List of AWS regions to be governed by Control Tower."

  validation {
    condition     = length(var.governed_regions) > 0
    error_message = "At least one governed region is required."
  }

  validation {
    condition     = alltrue([for r in var.governed_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", r))])
    error_message = "All governed regions must be valid AWS region codes."
  }
}

# ── Account IDs (from prerequisites) ──────────────────────────────────────────

variable "log_archive_account_id" {
  type        = string
  description = "AWS account ID of the Log Archive account."

  validation {
    condition     = can(regex("^\\d{12}$", var.log_archive_account_id))
    error_message = "log_archive_account_id must be a 12-digit AWS account ID."
  }
}

variable "security_tooling_account_id" {
  type        = string
  description = "AWS account ID of the Security Tooling (Audit) account."

  validation {
    condition     = can(regex("^\\d{12}$", var.security_tooling_account_id))
    error_message = "security_tooling_account_id must be a 12-digit AWS account ID."
  }
}

# ── Logging configuration ────────────────────────────────────────────────────

variable "logging_bucket_retention_days" {
  type        = number
  description = "Retention in days for the centralized logging bucket."
  default     = 365

  validation {
    condition     = var.logging_bucket_retention_days >= 1
    error_message = "Retention must be at least 1 day."
  }
}

variable "access_logging_bucket_retention_days" {
  type        = number
  description = "Retention in days for the access logging bucket."
  default     = 365

  validation {
    condition     = var.access_logging_bucket_retention_days >= 1
    error_message = "Retention must be at least 1 day."
  }
}

# ── AWS Config integration buckets ───────────────────────────────────────────
# AWS auto-fills these defaults when omitted, then reports drift on every
# subsequent plan because Terraform doesn't see them in the manifest.
# Defaults match what AWS Control Tower applies server-side.

variable "config_logging_bucket_retention_days" {
  type        = number
  description = "Retention in days for the AWS Config logging bucket."
  default     = 365

  validation {
    condition     = var.config_logging_bucket_retention_days >= 1
    error_message = "Retention must be at least 1 day."
  }
}

variable "config_access_logging_bucket_retention_days" {
  type        = number
  description = "Retention in days for the AWS Config access logging bucket."
  default     = 3650

  validation {
    condition     = var.config_access_logging_bucket_retention_days >= 1
    error_message = "Retention must be at least 1 day."
  }
}

# ── Access management ────────────────────────────────────────────────────────

variable "enable_access_management" {
  type        = bool
  description = "Whether CT manages IAM Identity Center access. Set to false if Identity Center is managed independently."
  default     = false
}

# ── Backup (optional) ────────────────────────────────────────────────────────

variable "enable_backup" {
  type        = bool
  description = "Whether to enable the AWS Backup integration in the CT manifest."
  default     = false
}

variable "backup_admin_account_id" {
  type        = string
  description = "AWS account ID of the Backup Administrator account. Required when enable_backup is true."
  default     = ""

  validation {
    condition     = var.backup_admin_account_id == "" || can(regex("^\\d{12}$", var.backup_admin_account_id))
    error_message = "backup_admin_account_id must be a 12-digit AWS account ID or empty."
  }

  validation {
    condition     = !var.enable_backup || var.backup_admin_account_id != ""
    error_message = "backup_admin_account_id is required when enable_backup is true."
  }
}

variable "backup_central_account_id" {
  type        = string
  description = "AWS account ID of the Central Backup account. Required when enable_backup is true."
  default     = ""

  validation {
    condition     = var.backup_central_account_id == "" || can(regex("^\\d{12}$", var.backup_central_account_id))
    error_message = "backup_central_account_id must be a 12-digit AWS account ID or empty."
  }

  validation {
    condition     = !var.enable_backup || var.backup_central_account_id != ""
    error_message = "backup_central_account_id is required when enable_backup is true."
  }

  validation {
    condition     = (var.backup_central_account_id == "") == (var.backup_admin_account_id == "")
    error_message = "Backup accounts must be provided together — set both backup_admin_account_id and backup_central_account_id, or neither."
  }
}

variable "backup_kms_key_arn" {
  type        = string
  description = "ARN of the multi-region KMS key for backup encryption. Required when enable_backup is true."
  default     = ""

  validation {
    condition     = var.backup_kms_key_arn == "" || can(regex("^arn:aws:kms:", var.backup_kms_key_arn))
    error_message = "backup_kms_key_arn must be a valid KMS key ARN or empty."
  }

  validation {
    condition     = !var.enable_backup || var.backup_kms_key_arn != ""
    error_message = "backup_kms_key_arn is required when enable_backup is true."
  }
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the Control Tower landing zone resource."
  default     = {}
}
