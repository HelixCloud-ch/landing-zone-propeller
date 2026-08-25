variable "region" {
  type        = string
  description = "AWS region."
}

# ── Pipeline inputs ───────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID (from VPC project output)."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the DB subnet group (from VPC project output)."
}


# ── Instance identity ─────────────────────────────────────────────────────────

variable "identifier" {
  type        = string
  description = "Unique identifier for the RDS instance."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.identifier))
    error_message = "Identifier must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 63 chars."
  }
}

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine" {
  type    = string
  default = "oracle-se2"
}

variable "engine_version" {
  type        = string
  description = "Oracle engine version (e.g. '19'). Use `aws rds describe-db-engine-versions --engine oracle-se2` to list available versions."
}

variable "license_model" {
  type    = string
  default = "license-included"
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 40
}

variable "storage_type" {
  type    = string
  default = "gp3"
}

variable "storage_encrypted" {
  type    = bool
  default = true
}

variable "kms_key_id" {
  type    = string
  default = null
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "db_name" {
  type    = string
  default = "ORCL"

  validation {
    condition     = can(regex("^[A-Z][A-Z0-9]{0,7}$", var.db_name))
    error_message = "db_name (Oracle SID) must be uppercase, alphanumeric, start with a letter, max 8 characters."
  }
}

variable "character_set_name" {
  type    = string
  default = "AL32UTF8"
}

variable "username" {
  type    = string
  default = "admin"
}

# ── Credential ────────────────────────────────────────────────────────────────

variable "credential" {
  type = object({
    # Identity — set exactly one, or leave all null for RDS-managed mode
    secret_name    = optional(string)
    secret_arn     = optional(string)
    parameter_name = optional(string)
    parameter_arn  = optional(string)

    # Password generation
    password = optional(object({
      length                     = optional(number, 28)
      exclude_characters         = optional(string, "/@\"\\'\n")
      exclude_lowercase          = optional(bool, false)
      exclude_numbers            = optional(bool, false)
      exclude_punctuation        = optional(bool, false)
      exclude_uppercase          = optional(bool, false)
      include_space              = optional(bool, false)
      require_each_included_type = optional(bool, true)
    }), {})

    # Rotation & encryption
    password_version = optional(number, 1)
    kms_key_id       = optional(string)
    description      = optional(string)
  })
  description = <<-EOT
    Credential strategy. Set one of secret_name/secret_arn/parameter_name/
    parameter_arn to use the ephemeral-credential module. Leave all null to
    use RDS-managed master password (manage_master_user_password=true with
    kms_key_id for encryption).
  EOT
  default     = {}
}

# ── Network access ────────────────────────────────────────────────────────────

variable "port" {
  type    = number
  default = 1521
}

variable "allowed_cidrs" {
  type    = list(string)
  default = []
}

variable "allowed_security_group_ids" {
  type    = list(string)
  default = []
}

# ── Availability ──────────────────────────────────────────────────────────────

variable "multi_az" {
  type    = bool
  default = false
}

# ── Backups & Maintenance ─────────────────────────────────────────────────────

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "backup_window" {
  type    = string
  default = "03:00-04:00"
}

variable "maintenance_window" {
  type    = string
  default = "sun:05:00-sun:06:00"
}

# ── Protection ────────────────────────────────────────────────────────────────

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Override for final snapshot name on deletion (used by sleep-snapshot mode)."
  default     = ""
}

variable "snapshot_identifier" {
  type        = string
  description = "DB snapshot to restore from on create (used by wake-snapshot mode). Empty = create fresh."
  default     = ""
}

# ── Upgrades ──────────────────────────────────────────────────────────────────

variable "auto_minor_version_upgrade" {
  type    = bool
  default = true
}

variable "apply_immediately" {
  type    = bool
  default = false
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "performance_insights_enabled" {
  type    = bool
  default = true
}

# ── S3 Integration ────────────────────────────────────────────────────────────

variable "enable_s3_integration" {
  type        = bool
  description = "Enable S3 integration for Oracle Data Pump import/export."
  default     = false
}

variable "enable_jvm" {
  type        = bool
  description = "Enable Oracle JVM (required for Spatial, Java stored procedures, and other features that depend on the JVM)."
  default     = false
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type    = map(string)
  default = {}
}

variable "consumer_tags" {
  type    = map(string)
  default = {}
}

variable "propeller_tags" {
  type    = map(string)
  default = {}
}
