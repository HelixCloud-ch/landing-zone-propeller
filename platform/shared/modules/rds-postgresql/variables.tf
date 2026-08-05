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
  description = "Port the PostgreSQL server listens on."
  default     = 5432
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

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine" {
  type        = string
  description = "RDS engine name."
  default     = "postgres"
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL major version (e.g. '16'). Minor version is auto-selected when auto_minor_version_upgrade is true."
  default     = "16"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class (e.g. 'db.m5.large', 'db.t3.medium'). Validated against orderable combinations."
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
  description = "KMS key ARN for storage encryption. Uses default aws/rds key if not specified. A CMK is required for cross-account AWS Backup copy."
  default     = null
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "db_name" {
  type        = string
  description = "Name of the initial database to create."
  default     = "appdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must start with a letter and contain only alphanumerics and underscores, max 63 chars."
  }
}

variable "username" {
  type        = string
  description = "Master username for the database."
  default     = "dbadmin"
}

variable "password" {
  type        = string
  description = "Master password. Used only when master_user_secret_kms_key_id is not set. Mutually exclusive with it. Ephemeral: never written to state or plan (delivered via the write-only password_wo argument)."
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "password_wo_version" {
  type        = number
  description = "Bump to rotate the write-only password. Only relevant in password mode."
  default     = 1
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key for a Secrets Manager-managed master password. When set, credentials are managed by Secrets Manager and 'password' must not be provided."
  default     = null
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

variable "snapshot_identifier" {
  type        = string
  description = "DB snapshot to restore from on create (e.g. for wake-from-sleep). Empty string means create fresh."
  default     = ""
}

# ── Protection ────────────────────────────────────────────────────────────────

variable "deletion_protection" {
  type        = bool
  description = "Prevent accidental deletion of the instance."
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot on deletion. Keep false so a snapshot is taken before destroy."
  default     = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Name for the final snapshot on deletion. If empty, defaults to '{identifier}-final'."
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

# ── Parameter Group ───────────────────────────────────────────────────────────

variable "parameter_group_name" {
  type        = string
  description = "DB parameter group name. Uses engine default if not specified."
  default     = null
}
