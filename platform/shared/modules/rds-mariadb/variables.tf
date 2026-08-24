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

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DB subnet group (data tier). At least 2 subnets in different AZs are required by RDS."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required (RDS requires subnets in at least 2 AZs)."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "All subnet_ids must be valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}

variable "port" {
  type        = number
  description = "Port the MariaDB server listens on."
  default     = 3306

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
  description = "RDS engine name."
  default     = "mariadb"

  validation {
    condition     = contains(["mariadb"], var.engine)
    error_message = "Engine must be 'mariadb'."
  }
}

variable "engine_version" {
  type        = string
  description = "MariaDB major version (e.g. '10.11'). Minor version is auto-selected when auto_minor_version_upgrade is true."
  default     = "10.11"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)*$", var.engine_version))
    error_message = "engine_version must be a numeric version string (e.g. '10.11' or '10.11.6')."
  }
}

variable "instance_class" {
  type        = string
  description = "RDS instance class (e.g. 'db.m5.large', 'db.t3.medium'). Validated against orderable combinations at plan time."
  default     = "db.t3.medium"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must follow the pattern db.<family>.<size> (e.g. db.t3.medium, db.m5.large)."
  }
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "allocated_storage" {
  type        = number
  description = "Initial allocated storage in GiB."
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "allocated_storage must be between 20 and 65536 GiB."
  }
}

variable "max_allocated_storage" {
  type        = number
  description = "Maximum storage in GiB for autoscaling. Set to 0 to disable."
  default     = 40

  validation {
    condition     = var.max_allocated_storage == 0 || var.max_allocated_storage >= var.allocated_storage
    error_message = "max_allocated_storage must be 0 (disabled) or >= allocated_storage."
  }
}

variable "storage_type" {
  type        = string
  description = "Storage type: 'gp3', 'io1', 'io2'."
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be one of: gp2, gp3, io1, io2."
  }
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

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws:kms:", var.kms_key_id))
    error_message = "kms_key_id must be a valid KMS key ARN (arn:aws:kms:...) or null."
  }
}

# ── Database ──────────────────────────────────────────────────────────────────

variable "db_name" {
  type        = string
  description = "Name of the initial database to create. Must begin with a letter; subsequent characters can be letters, underscores, or digits (1-64 chars)."
  default     = "appdb"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,63}$", var.db_name))
    error_message = "db_name must start with a letter, contain only letters, digits, and underscores, max 64 chars (MariaDB constraint)."
  }
}

variable "username" {
  type        = string
  description = "Master username for the database. MariaDB allows 1-16 letters or numbers, must start with a letter."
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,15}$", var.username))
    error_message = "username must start with a letter, contain only letters and digits, max 16 chars (MariaDB constraint)."
  }
}

variable "password" {
  type        = string
  description = "Master password. Used only when master_user_secret_kms_key_id is not set. Mutually exclusive with it. Ephemeral: never written to state or plan (delivered via the write-only password_wo argument). MariaDB allows 8-41 printable ASCII characters excluding '/', single-quote, '\"', '@', and spaces."
  sensitive   = true
  ephemeral   = true
  default     = null

  validation {
    condition     = var.password == null || (length(var.password) >= 8 && length(var.password) <= 41)
    error_message = "Password must be between 8 and 41 characters for MariaDB."
  }

  validation {
    condition     = var.password == null || can(regex("^[\\x21-\\x7E]*$", var.password))
    error_message = "Password must contain only printable ASCII characters (no spaces)."
  }

  validation {
    condition     = var.password == null || !can(regex("[/@\"']", var.password))
    error_message = "Password must not contain '/', '@', '\"', or single-quote (RDS MariaDB restriction)."
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
  description = "KMS key for a Secrets Manager-managed master password. When set, credentials are managed by Secrets Manager and 'password' must not be provided."
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
  description = "Days to retain automated backups (0 to disable, max 35)."
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35."
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

# ── Logging ───────────────────────────────────────────────────────────────────

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "List of log types to export to CloudWatch. Valid values for MariaDB: 'audit', 'error', 'general', 'slowquery'."
  default     = ["error", "slowquery"]

  validation {
    condition     = alltrue([for l in var.enabled_cloudwatch_logs_exports : contains(["audit", "error", "general", "slowquery"], l)])
    error_message = "enabled_cloudwatch_logs_exports entries must be one or more of: 'audit', 'error', 'general', 'slowquery'."
  }
}
