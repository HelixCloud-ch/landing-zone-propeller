variable "region" {
  type        = string
  description = "AWS region."
}

# ── Pipeline inputs ───────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID (from VPC project output)."
}

variable "subnet_ids_json" {
  type        = string
  description = "JSON string of subnet tier map (from VPC project output). Decoded to extract the selected tier."
}

variable "subnet_tier" {
  type        = string
  description = "Key in the subnet map to use for the DB subnet group."
  default     = "data"
}

# ── Instance identity ─────────────────────────────────────────────────────────

variable "identifier" {
  type        = string
  description = "Unique identifier for the Aurora cluster."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.identifier))
    error_message = "Identifier must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 63 chars."
  }
}

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL major version (e.g. '17')."
  default     = "17"
}

# ── Serverless v2 scaling ─────────────────────────────────────────────────────

variable "min_capacity" {
  type        = number
  description = "Minimum ACU. Set to 0 for scale-to-zero auto-pause."
  default     = 0
}

variable "max_capacity" {
  type        = number
  description = "Maximum ACU."
  default     = 4
}

variable "seconds_until_auto_pause" {
  type        = number
  description = "Idle seconds before auto-pause (when min_capacity=0). Range 300-86400."
  default     = 300
}

variable "instance_count" {
  type        = number
  description = "Number of Serverless v2 instances (1 writer + N-1 readers)."
  default     = 1
}

# ── Storage ───────────────────────────────────────────────────────────────────

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
  default = "appdb"
}

variable "username" {
  type    = string
  default = "dbadmin"
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
  default = 5432
}

variable "allowed_cidrs" {
  type    = list(string)
  default = []
}

variable "allowed_security_group_ids" {
  type    = list(string)
  default = []
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
  type    = string
  default = ""
}

variable "snapshot_identifier" {
  type    = string
  default = ""
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
  default = false
}

# ── Tags ──────────────────────────────────────────────────────────────────────

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
