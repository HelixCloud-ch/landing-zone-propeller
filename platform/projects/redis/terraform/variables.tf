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
  description = "Key in the subnet map to use for the subnet group."
  default     = "data"
}

# ── Instance identity ─────────────────────────────────────────────────────────

variable "identifier" {
  type        = string
  description = "Replication group identifier. Lowercase, alphanumeric and hyphens, max 40 chars."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.identifier))
    error_message = "Identifier must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 40 chars."
  }
}

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine" {
  type        = string
  description = "Cache engine: 'valkey' (recommended, 20% cheaper) or 'redis'."
  default     = "valkey"

  validation {
    condition     = contains(["valkey", "redis"], var.engine)
    error_message = "Engine must be 'valkey' or 'redis'."
  }
}

variable "engine_version" {
  type        = string
  description = "Engine version. For Valkey use '9.0', for Redis use '7.1'."
  default     = "9.0"
}

variable "node_type" {
  type        = string
  description = "ElastiCache node type (e.g. 'cache.t3.small', 'cache.m7g.large')."
  default     = "cache.t3.small"
}

variable "num_replicas" {
  type        = number
  description = "Number of read replicas (0 = primary only, no HA)."
  default     = 1

  validation {
    condition     = var.num_replicas >= 0 && var.num_replicas <= 5
    error_message = "num_replicas must be between 0 and 5."
  }
}

variable "parameter_group_name" {
  type        = string
  description = "Parameter group name. Defaults to engine default if null."
  default     = null
}

# ── Network access ────────────────────────────────────────────────────────────

variable "port" {
  type        = number
  description = "Port for Redis connections."
  default     = 6379
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to connect."
  default     = []
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to connect."
  default     = []
}

# ── Encryption & Auth ─────────────────────────────────────────────────────────

variable "transit_encryption_enabled" {
  type        = bool
  description = "Enable TLS for in-transit encryption."
  default     = true
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Enable encryption at rest."
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN for at-rest encryption. Uses default aws/elasticache key if null."
  default     = null
}

# ── Availability ──────────────────────────────────────────────────────────────

variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ with automatic failover. Requires num_replicas >= 1."
  default     = true
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Enable automatic failover. Requires num_replicas >= 1."
  default     = true
}

# ── Maintenance & Snapshots ───────────────────────────────────────────────────

variable "maintenance_window" {
  type        = string
  description = "Weekly maintenance window (UTC)."
  default     = "sun:05:00-sun:06:00"
}

variable "snapshot_retention_limit" {
  type        = number
  description = "Days to retain automatic snapshots (0 = disabled)."
  default     = 7
}

variable "snapshot_window" {
  type        = string
  description = "Daily snapshot window (UTC)."
  default     = "03:00-04:00"
}

# ── Upgrades ──────────────────────────────────────────────────────────────────

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Apply minor version upgrades automatically."
  default     = true
}

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately instead of during the next maintenance window."
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
