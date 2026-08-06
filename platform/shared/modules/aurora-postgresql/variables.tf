# ── Identity ──────────────────────────────────────────────────────────────────

variable "identifier" {
  type        = string
  description = "Unique identifier for the Aurora cluster. Used for naming all associated resources."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.identifier))
    error_message = "Identifier must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 63 chars."
  }
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID where the security group will be created."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DB subnet group (data tier). At least 2 subnets in different AZs are required."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required (Aurora requires subnets in at least 2 AZs)."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "All subnet_ids must be valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}

variable "port" {
  type        = number
  description = "Port the PostgreSQL server listens on."
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "Port must be between 1150 and 65535 (RDS restriction)."
  }
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to connect to the database."
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "All entries in allowed_cidrs must be valid CIDR blocks (e.g. 10.0.0.0/8)."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to connect to the database."
  default     = []

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", sg))])
    error_message = "All entries in allowed_security_group_ids must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}

variable "security_group_id" {
  type        = string
  description = "Existing security group to attach the cluster to. When set, the module does not create its own security group; ingress/egress rules are skipped — manage rules on the external group. Mutually exclusive with allowed_cidrs and allowed_security_group_ids."
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

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL major version (e.g. '17'). Auto-pause (min_capacity = 0) requires a recent version."
  default     = "17"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)*$", var.engine_version))
    error_message = "engine_version must be a numeric version string (e.g. '17' or '16.4')."
  }
}

# ── Serverless v2 scaling ─────────────────────────────────────────────────────

variable "min_capacity" {
  type        = number
  description = "Minimum Aurora Capacity Units (ACU). Set to 0 for scale-to-zero auto-pause."
  default     = 0

  validation {
    condition     = var.min_capacity >= 0 && var.min_capacity <= var.max_capacity
    error_message = "min_capacity must be >= 0 and <= max_capacity."
  }
}

variable "max_capacity" {
  type        = number
  description = "Maximum Aurora Capacity Units (ACU)."
  default     = 4

  validation {
    condition     = var.max_capacity >= 0.5 && var.max_capacity <= 256
    error_message = "max_capacity must be between 0.5 and 256 ACU."
  }
}

variable "seconds_until_auto_pause" {
  type        = number
  description = "Idle seconds before auto-pause when min_capacity is 0. Range 300-86400."
  default     = 300

  validation {
    condition     = var.seconds_until_auto_pause >= 300 && var.seconds_until_auto_pause <= 86400
    error_message = "seconds_until_auto_pause must be between 300 and 86400."
  }
}

variable "instance_count" {
  type        = number
  description = "Number of Serverless v2 instances (1 writer + N-1 readers)."
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 15
    error_message = "instance_count must be between 1 and 15."
  }
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "storage_encrypted" {
  type        = bool
  description = "Whether to encrypt storage at rest."
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN for storage encryption. Uses default aws/rds key if not specified."
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws:kms:", var.kms_key_id))
    error_message = "kms_key_id must be a valid KMS key ARN (arn:aws:kms:...) or null."
  }
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

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.username))
    error_message = "username must start with a letter and contain only alphanumerics and underscores, max 63 chars."
  }
}

variable "password" {
  type        = string
  description = "Master password (write-only, never in state). Mutually exclusive with master_user_secret_kms_key_id."
  sensitive   = true
  ephemeral   = true
  default     = null

  validation {
    condition     = var.password == null || (length(var.password) >= 8 && length(var.password) <= 128)
    error_message = "Password must be between 8 and 128 characters for Aurora PostgreSQL."
  }

  validation {
    condition     = var.password == null || can(regex("^[\\x21-\\x7E]*$", var.password))
    error_message = "Password must contain only printable ASCII characters (no spaces)."
  }

  validation {
    condition     = var.password == null || !can(regex("[/@\"]", var.password))
    error_message = "Password must not contain '/', '@', or '\"' (RDS restriction)."
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
  description = "KMS key for Secrets Manager-managed master password. When set, 'password' must not be provided."
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_id == null || can(regex("^arn:aws:kms:", var.master_user_secret_kms_key_id))
    error_message = "master_user_secret_kms_key_id must be a valid KMS key ARN or null."
  }
}

# ── Backups & Maintenance ─────────────────────────────────────────────────────

variable "backup_retention_period" {
  type        = number
  description = "Days to retain automated backups (1-35). Aurora does not allow 0."
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 (Aurora requires at least 1)."
  }
}

variable "backup_window" {
  type        = string
  description = "Daily time range for automated backups (UTC). Format: hh:mm-hh:mm."
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.backup_window))
    error_message = "backup_window must be in the format hh:mm-hh:mm (e.g. 03:00-04:00)."
  }
}

variable "maintenance_window" {
  type        = string
  description = "Weekly maintenance window (UTC). Format: ddd:hh:mm-ddd:hh:mm."
  default     = "sun:05:00-sun:06:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must be in the format ddd:hh:mm-ddd:hh:mm (e.g. sun:05:00-sun:06:00)."
  }
}

variable "snapshot_identifier" {
  type        = string
  description = "Cluster snapshot to restore from on create. Empty = create fresh."
  default     = ""
}

# ── Protection ────────────────────────────────────────────────────────────────

variable "deletion_protection" {
  type        = bool
  description = "Prevent accidental deletion of the cluster."
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot on deletion."
  default     = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Name for the final snapshot on deletion. Defaults to '{identifier}-final'."
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
  description = "Enable Performance Insights. Keep disabled with scale-to-zero (forces non-zero min ACU)."
  default     = false
}

# ── Parameter Group ───────────────────────────────────────────────────────────

variable "db_cluster_parameter_group_name" {
  type        = string
  description = "DB cluster parameter group name. Uses engine default if not specified."
  default     = null
}

variable "db_parameter_group_name" {
  type        = string
  description = "DB instance parameter group name. Uses engine default if not specified."
  default     = null
}
