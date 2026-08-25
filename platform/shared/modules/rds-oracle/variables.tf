# ── Identity ──────────────────────────────────────────────────────────────────

variable "identifier" {
  type        = string
  description = "Unique identifier for the RDS instance. Used for naming all associated resources."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.identifier))
    error_message = "Identifier must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 63 chars."
  }
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID where the security group will be created."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DB subnet group (data tier)."
}

variable "port" {
  type        = number
  description = "Port the Oracle listener runs on."
  default     = 1521
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to connect to the database."
  default     = []
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to connect to the database."
  default     = []
}

variable "security_group_id" {
  type        = string
  description = "Existing security group ID to use instead of creating one. When set, the module skips SG creation and all ingress/egress rule management — manage rules on the external group. Mutually exclusive with allowed_cidrs and allowed_security_group_ids."
  default     = null

  validation {
    condition     = var.security_group_id == null || can(regex("^sg-[0-9a-f]{8,17}$", var.security_group_id))
    error_message = "security_group_id must be a valid security group ID (e.g. sg-0123456789abcdef0) or null."
  }

  validation {
    condition     = var.security_group_id == null || (length(var.allowed_cidrs) == 0 && length(var.allowed_security_group_ids) == 0)
    error_message = "When security_group_id is provided, do not set allowed_cidrs or allowed_security_group_ids — manage rules on the external group instead."
  }
}

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine" {
  type        = string
  description = "RDS engine name. Use 'oracle-se2' for Standard Edition Two, 'oracle-ee' for Enterprise."
  default     = "oracle-se2"
}

variable "engine_version" {
  type        = string
  description = "Oracle engine version (e.g. '19' or '19.0.0.0.0'). The major version is extracted automatically for the option group."
}

variable "license_model" {
  type        = string
  description = "License model: 'license-included' (AWS provides license) or 'bring-your-own-license'."
  default     = "license-included"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class (e.g. 'db.m5.large', 'db.t3.medium')."
  default     = "db.t3.medium"
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "allocated_storage" {
  type        = number
  description = "Initial allocated storage in GiB."
  default     = 20
}

variable "max_allocated_storage" {
  type        = number
  description = "Maximum storage in GiB for autoscaling. Set to 0 to disable."
  default     = 40
}

variable "storage_type" {
  type        = string
  description = "Storage type: 'gp3', 'io1', 'io2'."
  default     = "gp3"
}

variable "storage_encrypted" {
  type        = bool
  description = "Whether to encrypt storage at rest."
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN for storage encryption. Uses default aws/rds key if not specified."
  default     = null
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "db_name" {
  type        = string
  description = "Oracle SID (database name). Must be uppercase, max 8 chars for Oracle."
  default     = "ORCL"

  validation {
    condition     = can(regex("^[A-Z][A-Z0-9]{0,7}$", var.db_name))
    error_message = "db_name (Oracle SID) must be uppercase, alphanumeric, start with a letter, max 8 characters."
  }
}

variable "character_set_name" {
  type        = string
  description = "Database character set. Cannot be changed after creation."
  default     = "AL32UTF8"
}

variable "username" {
  type        = string
  description = "Master username for the database."
  default     = "admin"
}

variable "password" {
  type        = string
  description = <<-EOT
    Master password. Used only when master_user_secret_kms_key_id is not set.
    Ephemeral: never written to state (delivered via password_wo).
  EOT
  sensitive   = true
  ephemeral   = true
  default     = null

  validation {
    condition     = var.password == null || (length(var.password) >= 8 && length(var.password) <= 30)
    error_message = "Password must be between 8 and 30 characters for Oracle."
  }

  validation {
    condition     = var.password == null || can(regex("^[\\x21-\\x7E]*$", var.password))
    error_message = "Password must contain only printable ASCII characters (no spaces)."
  }

  validation {
    condition     = var.password == null || !can(regex("[/@\"']", var.password))
    error_message = "Password must not contain '/', '@', '\"', or single quote (RDS Oracle restriction)."
  }

  validation {
    condition     = !(var.password != null && var.master_user_secret_kms_key_id != null)
    error_message = "Pass either 'password' or 'master_user_secret_kms_key_id', not both."
  }

  validation {
    condition     = var.snapshot_identifier != "" || var.password != null || var.master_user_secret_kms_key_id != null
    error_message = "Provide credentials: set 'master_user_secret_kms_key_id' for Secrets Manager mode, or 'password' for password mode (unless restoring from a snapshot)."
  }
}

variable "password_wo_version" {
  type        = number
  description = "Bump to rotate the write-only password. Only relevant in password mode."
  default     = 1
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key for a Secrets Manager-managed master password. When set, RDS manages rotation and 'password' must not be provided."
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_id == null || can(regex("^arn:aws:kms:", var.master_user_secret_kms_key_id))
    error_message = "master_user_secret_kms_key_id must be a valid KMS key ARN or null."
  }
}

# ── Availability ──────────────────────────────────────────────────────────────

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment for high availability."
  default     = false
}

# ── Backups & Maintenance ─────────────────────────────────────────────────────

variable "backup_retention_period" {
  type        = number
  description = "Days to retain automated backups (0 to disable)."
  default     = 7
}

variable "backup_window" {
  type        = string
  description = "Daily time range for automated backups (UTC). Must not overlap maintenance_window."
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  type        = string
  description = "Weekly maintenance window (UTC)."
  default     = "sun:05:00-sun:06:00"
}

# ── Protection ────────────────────────────────────────────────────────────────

variable "deletion_protection" {
  type        = bool
  description = "Prevent accidental deletion of the instance."
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot on deletion. Set to false for production."
  default     = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Name for the final snapshot on deletion. If empty, defaults to '{identifier}-final'."
  default     = ""
}

variable "snapshot_identifier" {
  type        = string
  description = "DB snapshot to restore from (e.g. for wake-from-sleep). Empty string means create fresh."
  default     = ""
}

# ── Upgrades ──────────────────────────────────────────────────────────────────

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Apply minor version upgrades automatically during the maintenance window."
  default     = true
}

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately instead of during the next maintenance window."
  default     = false
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "performance_insights_enabled" {
  type        = bool
  description = "Enable Performance Insights."
  default     = true
}

# ── Parameter & Option Groups ─────────────────────────────────────────────────

variable "parameter_group_name" {
  type        = string
  description = "DB parameter group name. Uses engine default if not specified."
  default     = null
}

# ── S3 Integration ────────────────────────────────────────────────────────────

variable "enable_s3_integration" {
  type        = bool
  description = "Enable S3 integration (creates bucket, IAM role, adds S3_INTEGRATION to the option group)."
  default     = false
}

# ── JVM ───────────────────────────────────────────────────────────────────────

variable "enable_jvm" {
  type        = bool
  description = "Enable Oracle JVM (adds JVM option to the option group). Required for Spatial, Java stored procedures, and other features that depend on the JVM."
  default     = false
}

# ── Additional Options ────────────────────────────────────────────────────────

variable "additional_options" {
  type = list(object({
    option_name = string
    version     = optional(string)
    port        = optional(number)
    settings = optional(list(object({
      name  = string
      value = string
    })), [])
  }))
  description = "Additional options to include in the module-managed option group (e.g. APEX, native network encryption)."
  default     = []
}
