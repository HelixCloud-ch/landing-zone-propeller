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

# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_identifier" {
  type        = string
  description = "Unique identifier for the DocumentDB cluster."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.cluster_identifier)) && !can(regex("--", var.cluster_identifier)) && !can(regex("-$", var.cluster_identifier))
    error_message = "Cluster identifier must be 1-63 chars, lowercase, start with a letter, alphanumerics and hyphens only, no consecutive/trailing hyphens."
  }
}

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine_version" {
  type        = string
  description = "DocumentDB engine version (e.g. '8.0.0')."
  default     = "8.0.0"
}

# ── Instances ─────────────────────────────────────────────────────────────────

variable "instance_count" {
  type        = number
  description = "Number of cluster instances (1 writer + N-1 readers)."
  default     = 1
}

variable "instance_class" {
  type        = string
  description = "Instance class for cluster instances."
  default     = "db.t3.medium"
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

variable "storage_type" {
  type    = string
  default = "standard"
}

# ── Authentication ────────────────────────────────────────────────────────────

variable "master_username" {
  type    = string
  default = "docdbadmin"
}

variable "master_password" {
  type        = string
  description = "Master password. When set, credentials are managed manually (not via Secrets Manager). Ephemeral: never stored in state. 8-100 printable ASCII chars excluding '/', '\"', '@'."
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "master_password_wo_version" {
  type        = number
  description = "Bump to rotate the write-only password. Only relevant when master_password is set."
  default     = 1
}

# ── Network access ────────────────────────────────────────────────────────────

variable "port" {
  type    = number
  default = 27017
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

variable "preferred_backup_window" {
  type    = string
  default = "03:00-04:00"
}

variable "preferred_maintenance_window" {
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

variable "apply_immediately" {
  type    = bool
  default = false
}

variable "allow_major_version_upgrade" {
  type    = bool
  default = true
}

# ── Parameters ────────────────────────────────────────────────────────────────

variable "cluster_parameters" {
  type        = map(string)
  description = "DocumentDB cluster parameter group parameters (e.g. {tls = \"enabled\"})."
  default     = {}
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "enable_performance_insights" {
  type    = bool
  default = true
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "enabled_cloudwatch_logs_exports" {
  type    = list(string)
  default = ["audit"]
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
