# ── Identity ──────────────────────────────────────────────────────────────────

variable "cluster_identifier" {
  type        = string
  description = "Unique identifier for the DocumentDB cluster. Used for naming all associated resources."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.cluster_identifier)) && !can(regex("--", var.cluster_identifier)) && !can(regex("-$", var.cluster_identifier))
    error_message = "Cluster identifier must be 1-63 chars, lowercase, start with a letter, contain only alphanumerics and hyphens, no consecutive hyphens, no trailing hyphen."
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
  description = "List of subnet IDs for the DB subnet group. At least 2 subnets in different AZs are required."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required (DocumentDB requires subnets in at least 2 AZs)."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "All subnet_ids must be valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}

variable "port" {
  type        = number
  description = "Port the DocumentDB cluster listens on."
  default     = 27017

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "Port must be between 1150 and 65535."
  }
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to connect to the cluster."
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "All entries in allowed_cidrs must be valid CIDR blocks (e.g. 10.0.0.0/8)."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to connect to the cluster."
  default     = []

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", sg))])
    error_message = "All entries in allowed_security_group_ids must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }
}

variable "security_group_id" {
  type        = string
  description = "Existing security group ID to use instead of creating one. When set, the module skips SG creation and all ingress rule management. Mutually exclusive with allowed_cidrs and allowed_security_group_ids."
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
  description = "DocumentDB engine version (e.g. '8.0.0', '5.0.0'). Validated at plan time against available versions in the target region."
  default     = "8.0.0"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)*$", var.engine_version))
    error_message = "engine_version must be a numeric version string (e.g. '8.0.0' or '5.0.0')."
  }
}

# ── Instances ─────────────────────────────────────────────────────────────────

variable "instance_count" {
  type        = number
  description = "Number of cluster instances (1 writer + N-1 readers). Minimum 1."
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 16
    error_message = "instance_count must be between 1 and 16."
  }
}

variable "instance_class" {
  type        = string
  description = "Instance class for cluster instances (e.g. 'db.r6g.large', 'db.t3.medium')."
  default     = "db.t3.medium"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must follow the pattern db.<family>.<size> (e.g. db.t3.medium, db.r6g.large)."
  }
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "storage_encrypted" {
  type        = bool
  description = "Whether to encrypt cluster storage at rest. Enabled by default (cannot be changed after creation)."
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN for storage encryption. Uses default aws/docdb key if not specified."
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws:kms:", var.kms_key_id))
    error_message = "kms_key_id must be a valid KMS key ARN (arn:aws:kms:...) or null."
  }
}

variable "storage_type" {
  type        = string
  description = "Storage type for the cluster: 'standard' or 'iopt1' (I/O-optimized)."
  default     = "standard"

  validation {
    condition     = contains(["standard", "iopt1"], var.storage_type)
    error_message = "storage_type must be 'standard' or 'iopt1'."
  }
}

# ── Authentication ────────────────────────────────────────────────────────────

variable "master_username" {
  type        = string
  description = "Master username for the cluster. 1-63 alphanumeric chars, starts with a letter."
  default     = "docdbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,62}$", var.master_username))
    error_message = "master_username must start with a letter, contain only letters and digits, max 63 chars."
  }
}

variable "master_password" {
  type        = string
  description = "Master password. Used only when master_user_secret_kms_key_id is not set. Ephemeral: never written to state (delivered via write-only argument). 8-100 printable ASCII chars excluding '/', '\"', '@'."
  sensitive   = true
  ephemeral   = true
  default     = null

  validation {
    condition     = var.master_password == null || (length(var.master_password) >= 8 && length(var.master_password) <= 100)
    error_message = "Password must be between 8 and 100 characters for DocumentDB."
  }

  validation {
    condition     = var.master_password == null || can(regex("^[\\x21-\\x7E]*$", var.master_password))
    error_message = "Password must contain only printable ASCII characters (no spaces)."
  }

  validation {
    condition     = var.master_password == null || !can(regex("[/@\"]", var.master_password))
    error_message = "Password must not contain '/', '@', or '\"' (DocumentDB restriction)."
  }

  validation {
    condition     = !(var.master_password != null && var.master_user_secret_kms_key_id != null)
    error_message = "Pass either 'master_password' or 'master_user_secret_kms_key_id', not both."
  }

  validation {
    condition     = var.snapshot_identifier != "" || var.master_password != null || var.master_user_secret_kms_key_id != null
    error_message = "Provide credentials: set 'master_user_secret_kms_key_id' for Secrets Manager mode, or 'master_password' for password mode (unless restoring from a snapshot)."
  }
}

variable "master_password_wo_version" {
  type        = number
  description = "Bump to rotate the write-only password. Only relevant in password mode."
  default     = 1
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key ARN for Secrets Manager-managed master password. When set, credentials are managed by Secrets Manager."
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_id == null || can(regex("^arn:aws:kms:", var.master_user_secret_kms_key_id))
    error_message = "master_user_secret_kms_key_id must be a valid KMS key ARN or null."
  }
}

# ── Backups & Maintenance ─────────────────────────────────────────────────────

variable "backup_retention_period" {
  type        = number
  description = "Days to retain automated backups (1 to 35)."
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35."
  }
}

variable "preferred_backup_window" {
  type        = string
  description = "Daily time range for automated backups (UTC). Format: hh:mm-hh:mm."
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.preferred_backup_window))
    error_message = "preferred_backup_window must be in the format hh:mm-hh:mm (e.g. 03:00-04:00)."
  }
}

variable "preferred_maintenance_window" {
  type        = string
  description = "Weekly maintenance window (UTC). Format: ddd:hh:mm-ddd:hh:mm."
  default     = "sun:05:00-sun:06:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "preferred_maintenance_window must be in the format ddd:hh:mm-ddd:hh:mm (e.g. sun:05:00-sun:06:00)."
  }
}

variable "snapshot_identifier" {
  type        = string
  description = "Cluster snapshot to restore from on create. Empty string means create fresh."
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
  description = "Skip final snapshot on deletion. Keep false so a snapshot is taken before destroy."
  default     = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Name for the final snapshot on deletion. If empty, defaults to '{cluster_identifier}-final'."
  default     = ""
}

# ── Upgrades ──────────────────────────────────────────────────────────────────

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately instead of during the next maintenance window."
  default     = false
}

variable "allow_major_version_upgrade" {
  type        = bool
  description = "Allow major engine version upgrades when changing engine_version."
  default     = true
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "enable_performance_insights" {
  type        = bool
  description = "Enable Performance Insights on cluster instances."
  default     = true
}

# ── Parameter Group ───────────────────────────────────────────────────────────

variable "cluster_parameters" {
  type        = map(string)
  description = "Map of DocumentDB cluster parameter group parameters. The parameter group is created automatically with the correct family derived from engine_version."
  default     = {}
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "List of log types to export to CloudWatch. Valid values for DocumentDB: 'audit', 'profiler'."
  default     = ["audit"]

  validation {
    condition     = alltrue([for l in var.enabled_cloudwatch_logs_exports : contains(["audit", "profiler"], l)])
    error_message = "enabled_cloudwatch_logs_exports entries must be 'audit' and/or 'profiler'."
  }
}
