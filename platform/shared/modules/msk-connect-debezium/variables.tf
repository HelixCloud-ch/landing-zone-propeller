# ── Identity ──────────────────────────────────────────────────────────────────

variable "identifier" {
  type        = string
  description = "Unique connector identifier. Names all associated resources and seeds the deterministic Debezium server id."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,55}$", var.identifier))
    error_message = "identifier must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 56 chars."
  }
}

variable "region" {
  type        = string
  description = "AWS region as a literal, used for the SSM Config_Provider in the worker configuration. Passed by the project from its own region variable."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources that take a tags map. The project passes the merged tag set; the module does not know propeller's tag triple."
  default     = {}
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID where the connector security group is created."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs the connector's ENIs are placed in. Must reach the database and the Kafka brokers."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet ID is required."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "All subnet_ids must be valid subnet IDs (e.g. subnet-0123456789abcdef0)."
  }
}

variable "db_host" {
  type        = string
  description = "Hostname of the source database the connector reads from."
}

variable "db_port" {
  type        = number
  description = "Port of the source database. Opened as an egress rule on the connector security group."
  default     = 3306

  validation {
    condition     = var.db_port >= 1 && var.db_port <= 65535
    error_message = "db_port must be between 1 and 65535."
  }
}

variable "db_name" {
  type        = string
  description = "Oracle service name / SID (database.dbname). Ignored by the mariadb template. On a CDB instance this is the container database's service; see pdb_name to target a pluggable database instead."
  default     = ""
}

variable "pdb_name" {
  type        = string
  description = "Oracle pluggable database name (database.pdb.name), for a multitenant (CDB) source. Empty (default) omits the property entirely — a non-CDB instance has no PDB to name. Ignored by the mariadb template."
  default     = ""
}

variable "broker_port" {
  type        = number
  description = "Kafka broker port the connector connects to. Opened as an egress rule on the connector security group."
  default     = 9098

  validation {
    condition     = var.broker_port >= 1 && var.broker_port <= 65535
    error_message = "broker_port must be between 1 and 65535."
  }
}

variable "bootstrap_servers" {
  type        = string
  description = "Kafka bootstrap servers string the connector and the schema-history writer connect to."
}

# ── Plugin ────────────────────────────────────────────────────────────────────

variable "custom_plugin_arn" {
  type        = string
  description = "ARN of the registered MSK Connect custom plugin. Changing it forces connector replacement (MSK Connect connectors are immutable wrt their plugin)."

  validation {
    condition     = can(regex("^arn:aws:kafkaconnect:", var.custom_plugin_arn))
    error_message = "custom_plugin_arn must be a valid MSK Connect custom plugin ARN (arn:aws:kafkaconnect:...)."
  }
}

variable "custom_plugin_revision" {
  type        = number
  description = "Revision of the custom plugin to pin. Defaults to 1, the revision an MSK Connect custom plugin is created with."
  default     = 1
}

# ── Worker configuration / topics ─────────────────────────────────────────────

variable "offset_topic" {
  type        = string
  description = "Kafka topic where the connector stores source offsets. Declared in the worker configuration."
}

variable "schema_history_topic" {
  type        = string
  description = "Kafka topic where Debezium stores captured schema history."
}

variable "topic_prefix" {
  type        = string
  description = "Debezium topic prefix. Effectively immutable: changing it orphans existing topics and breaks schema-history recovery."
}

variable "server_id" {
  type        = string
  description = "Debezium database.server.id. Must be stable per connector and unique across connectors; the project derives it deterministically from identifier."
}

# ── Credentials ───────────────────────────────────────────────────────────────

variable "cdc_username_parameter" {
  type        = string
  description = "Name of the SSM parameter holding the CDC user name. Referenced literally in the connector config via the SSM Config_Provider."
}

variable "cdc_password_parameter" {
  type        = string
  description = "Name of the SSM parameter holding the CDC user password. Referenced literally in the connector config via the SSM Config_Provider."
}

variable "cdc_username_parameter_arn" {
  type        = string
  description = "ARN of the CDC username SSM parameter. The service execution role is granted ssm:GetParameter on exactly this ARN."

  validation {
    condition     = can(regex("^arn:aws:ssm:", var.cdc_username_parameter_arn))
    error_message = "cdc_username_parameter_arn must be a valid SSM parameter ARN (arn:aws:ssm:...)."
  }
}

variable "cdc_password_parameter_arn" {
  type        = string
  description = "ARN of the CDC password SSM parameter. The service execution role is granted ssm:GetParameter on exactly this ARN."

  validation {
    condition     = can(regex("^arn:aws:ssm:", var.cdc_password_parameter_arn))
    error_message = "cdc_password_parameter_arn must be a valid SSM parameter ARN (arn:aws:ssm:...)."
  }
}

variable "cdc_kms_key_id" {
  type        = string
  description = <<-EOT
    KMS key that encrypts the two CDC SecureString parameters, as an alias
    name, key id, or key ARN. Determines whether the service execution role
    needs kms:Decrypt: the default AWS-managed key (alias/aws/ssm) grants
    decrypt implicitly and cannot be named in an IAM Resource, so no statement
    is added; any other (customer-managed) key is resolved to its real key ARN
    and granted kms:Decrypt. See README.
  EOT
  default     = "alias/aws/ssm"
}

# ── Kafka authentication ──────────────────────────────────────────────────────

variable "kafka_cluster_arn" {
  type        = string
  description = "ARN of the target MSK cluster. Scopes the kafka-cluster:* grants when client_authentication is IAM."

  validation {
    condition     = can(regex("^arn:aws:kafka:", var.kafka_cluster_arn))
    error_message = "kafka_cluster_arn must be a valid MSK cluster ARN (arn:aws:kafka:...)."
  }
}

variable "client_authentication" {
  type        = string
  description = "MSK Connect client authentication. NONE grants no kafka-cluster permissions; IAM adds them. SASL/SCRAM is unavailable to a connector."
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "IAM"], var.client_authentication)
    error_message = "client_authentication must be NONE or IAM (the only values MSK Connect accepts)."
  }
}

variable "in_transit_encryption" {
  type        = string
  description = "Encryption in transit to the cluster: PLAINTEXT or TLS. Independent of client_authentication, with no built-in assumption."
  default     = "PLAINTEXT"

  validation {
    condition     = contains(["PLAINTEXT", "TLS"], var.in_transit_encryption)
    error_message = "in_transit_encryption must be PLAINTEXT or TLS."
  }
}

# ── Capture scope ─────────────────────────────────────────────────────────────

variable "table_include_list" {
  type        = string
  description = "Comma-separated Debezium table.include.list. Empty string captures everything: the template omits the property entirely rather than emitting a wildcard."
  default     = ""
}

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine" {
  type        = string
  description = "Source engine. Selects the connector config template config/<engine>.tftpl."
  default     = "mariadb"

  validation {
    condition     = contains(["mariadb", "oracle"], var.engine)
    error_message = "engine must be 'mariadb' or 'oracle'."
  }
}

variable "log_mining_strategy" {
  type        = string
  description = <<-EOT
    Oracle LogMiner's log.mining.strategy. Ignored by the mariadb template.
    'hybrid' (default) tracks DDL changes without the extra archive-log
    volume 'redo_log_catalog' generates, and is the currently-recommended
    replacement for 'redo_log_catalog', which is deprecated and scheduled
    for removal in a future Debezium release. 'online_catalog' mines faster
    but cannot track DDL changes against captured tables — choose it only
    when the captured tables' schema changes infrequently or never. See the
    module README for the full tradeoff.
  EOT
  default     = "hybrid"

  validation {
    condition     = contains(["hybrid", "online_catalog", "redo_log_catalog"], var.log_mining_strategy)
    error_message = "log_mining_strategy must be 'hybrid', 'online_catalog', or 'redo_log_catalog' (deprecated)."
  }
}

variable "kafkaconnect_version" {
  type        = string
  description = "Kafka Connect version for the connector. MSK Connect supports 2.7.1 and 3.7.x only."
  default     = "3.7.x"
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "log_retention_in_days" {
  type        = number
  description = "Retention for the connector log group. Finite by default, overridable by the consumer."
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts (e.g. 1, 7, 30, 90, 365, 0 for never expire)."
  }
}

# ── Alarm ─────────────────────────────────────────────────────────────────────

variable "alarm_actions" {
  type        = list(string)
  description = "Actions for the not-running alarm (e.g. SNS topic ARNs). Defaults to empty: the framework has no notification-target convention yet."
  default     = []
}
