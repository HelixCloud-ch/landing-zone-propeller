variable "region" {
  type        = string
  description = "AWS region."
}

# ── Identity ──────────────────────────────────────────────────────────────────

variable "identifier" {
  type        = string
  description = "Unique connector identifier. Names all module resources and seeds the deterministic Debezium server id."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,55}$", var.identifier))
    error_message = "identifier must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 56 chars."
  }
}

# ── Network (from workload VPC project output) ─────────────────────────────────

variable "vpc_id" {
  type        = string
  description = "VPC ID where the connector security group is created (from VPC project output)."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the connector ENIs. Must reach the database and the Kafka brokers (from VPC project output)."
}

# ── Source database ────────────────────────────────────────────────────────────

variable "db_host" {
  type        = string
  description = "Hostname of the source database the connector reads from."
}

variable "db_port" {
  type        = number
  description = "Port of the source database. Opened as connector egress."
  default     = 3306
}

variable "db_name" {
  type        = string
  description = "Oracle service name / SID (database.dbname). Ignored for engine = \"mariadb\"."
  default     = ""
}

variable "pdb_name" {
  type        = string
  description = "Oracle pluggable database name (database.pdb.name), for a multitenant (CDB) source. Empty (default) omits the property. Ignored for engine = \"mariadb\"."
  default     = ""
}

# ── Kafka ──────────────────────────────────────────────────────────────────────

variable "bootstrap_servers" {
  type        = string
  description = "Kafka bootstrap servers string the connector connects to."
}

variable "broker_port" {
  type        = number
  description = "Kafka broker port. Opened as connector egress."
  default     = 9098
}

variable "kafka_cluster_arn" {
  type        = string
  description = "ARN of the target MSK cluster. Scopes the kafka-cluster:* grants when client_authentication is IAM."
}

variable "client_authentication" {
  type        = string
  description = "MSK Connect client authentication: NONE (no kafka-cluster grants) or IAM (adds them)."
  default     = "NONE"
}

variable "in_transit_encryption" {
  type        = string
  description = "Encryption in transit to the cluster: PLAINTEXT or TLS."
  default     = "PLAINTEXT"
}

# ── Plugin (from msk-connect-plugin project output) ────────────────────────────

# The plugin ARN/revision cannot be selected by the pipeline: a propeller input
# reads one whole output field and cannot sub-address a map key (see
# docs/pipeline-schema.md § Path resolution). So the project takes the whole
# plugin maps published by msk-connect-plugin and selects the entry itself, by
# engine (the flavour) plus an optional plugin_version. The maps are consumed as
# native Terraform maps — propeller round-trips a map output to a map variable
# without JSON encoding, since HCL variable values are a JSON superset.

variable "plugin_arns" {
  type        = map(string)
  description = "Custom plugin ARNs keyed by \"<flavour>-<version>\" (msk-connect-plugin.plugin_arns). Used when plugin_version is set to pin a specific version."
  default     = {}
}

variable "plugin_revisions" {
  type        = map(number)
  description = "Custom plugin revisions keyed by \"<flavour>-<version>\" (msk-connect-plugin.plugin_revisions). Used with plugin_version."
  default     = {}
}

variable "default_plugin_arns" {
  type        = map(string)
  description = "Custom plugin ARNs of the default version, keyed by flavour (msk-connect-plugin.default_plugin_arns). Used when plugin_version is empty."
  default     = {}
}

variable "default_plugin_revisions" {
  type        = map(number)
  description = "Custom plugin revisions of the default version, keyed by flavour (msk-connect-plugin.default_plugin_revisions). Used when plugin_version is empty."
  default     = {}
}

variable "plugin_version" {
  type        = string
  description = <<-EOT
    Pin a specific plugin version for this connector's engine. Empty (default)
    uses the flavour's default from default_plugin_arns; a non-empty value
    selects "<engine>-<version>" from plugin_arns. Changing the resolved plugin
    forces connector replacement. See README for the default-vs-pinned selection.
  EOT
  default     = ""

  validation {
    condition = (
      var.plugin_version == ""
      ? contains(keys(var.default_plugin_arns), var.engine)
      : contains(keys(var.plugin_arns), "${var.engine}-${var.plugin_version}")
    )
    error_message = "No plugin ARN for the requested engine/version: with plugin_version empty, engine must be a key in default_plugin_arns; otherwise \"<engine>-<plugin_version>\" must be a key in plugin_arns. Check the maps wired from msk-connect-plugin."
  }
}

# ── Worker configuration / topics ──────────────────────────────────────────────

variable "offset_topic" {
  type        = string
  description = "Kafka topic where the connector stores source offsets."
}

variable "schema_history_topic" {
  type        = string
  description = "Kafka topic where Debezium stores captured schema history."
}

variable "topic_prefix" {
  type        = string
  description = "Debezium topic prefix. Effectively immutable: changing it orphans existing topics."
}

variable "server_id" {
  type        = string
  description = <<-EOT
    Debezium database.server.id. Must be stable per connector and unique
    across connectors. Leave null to derive it deterministically from
    identifier (see README for the derivation).
  EOT
  default     = null
}

# ── CDC credentials (from cdc-prepare-mariadb) ─────────────────────────────────

variable "cdc_username_parameter" {
  type        = string
  description = "Name of the SSM parameter holding the CDC username (created by cdc-prepare-*). The project derives its ARN for the connector's IAM policy; the module reads the value at connector-start via the SSM Config Provider."
}

variable "cdc_password_parameter" {
  type        = string
  description = "Name of the SSM parameter holding the CDC password (created by cdc-prepare-*). The project derives its ARN for the connector's IAM policy; the module reads the value at connector-start via the SSM Config Provider."
}

variable "cdc_kms_key_id" {
  type        = string
  description = "KMS key encrypting the CDC SecureString parameters (alias/id/ARN). Default alias/aws/ssm adds no kms:Decrypt; a customer-managed key is resolved to its ARN and granted. See module README."
  default     = "alias/aws/ssm"
}

# ── Capture scope ──────────────────────────────────────────────────────────────

variable "tables" {
  type        = string
  description = <<-EOT
    JSON list of fully-qualified tables to capture. Locals join it into the
    module's table_include_list; an empty list ("[]") captures everything.
  EOT
  default     = "[]"
}

# ── Engine ─────────────────────────────────────────────────────────────────────

variable "engine" {
  type        = string
  description = "Source engine selecting the module's config template."
  default     = "mariadb"

  validation {
    condition     = contains(["mariadb", "oracle"], var.engine)
    error_message = "engine must be 'mariadb' or 'oracle'."
  }
}

variable "log_mining_strategy" {
  type        = string
  description = "Oracle LogMiner's log.mining.strategy. Ignored for engine = \"mariadb\". See the module README for the tradeoff between 'hybrid' (default), 'online_catalog' and the deprecated 'redo_log_catalog'."
  default     = "hybrid"

  validation {
    condition     = contains(["hybrid", "online_catalog", "redo_log_catalog"], var.log_mining_strategy)
    error_message = "log_mining_strategy must be 'hybrid', 'online_catalog', or 'redo_log_catalog' (deprecated)."
  }
}

# ── Logging & alarm (passthrough) ──────────────────────────────────────────────

variable "log_retention_in_days" {
  type        = number
  description = "Retention for the connector log group. Passed through to the module."
  default     = 30
}

variable "alarm_actions" {
  type        = list(string)
  description = "Actions for the connector not-running alarm (e.g. SNS topic ARNs). Empty by default."
  default     = []
}

# ── Tags (propeller-injected) ──────────────────────────────────────────────────

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
