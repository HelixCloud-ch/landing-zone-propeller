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
  description = "JSON string of subnet tier map (from VPC project output). Decoded to extract the data tier."
}

variable "subnet_tier" {
  type        = string
  description = "Key in the subnet map to use for the DB subnet group."
  default     = "data"
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
