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
  description = "VPC ID for the connector security group. Required only when create_security_group is true."
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the connector ENIs. Must reach the database and the Kafka brokers (from VPC project output)."
}

variable "create_security_group" {
  type        = bool
  description = "Create the connector security group. Set false to use only security_group_ids."
  default     = true
  nullable    = false
}

variable "security_group_ids" {
  type        = list(string)
  description = "Existing security groups for the connector ENIs, added to the created one (if any)."
  default     = []
  nullable    = false
}

variable "additional_egress_rules" {
  type = map(object({
    from_port                    = number
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    description                  = optional(string)
  }))
  description = "Extra egress rules on the created security group, keyed by a stable name."
  default     = {}
  nullable    = false
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
  description = "ARN of the target MSK cluster. Required for IAM auth when the module creates the role."
  default     = null
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
  description = "Kafka topic for source offsets. Required unless worker_configuration_arn is set."
  default     = null
}

variable "worker_configuration_arn" {
  type        = string
  description = "Existing MSK Connect worker configuration to use instead of creating one."
  default     = null
}

variable "worker_configuration_revision" {
  type        = number
  description = "Revision of worker_configuration_arn. Set both or neither."
  default     = null
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
  description = <<-EOT
    Name of the SSM parameter holding the CDC username (from cdc-prepare-*).
    Null (both) = no derived credentials; supply them via the connector
    config. See README.
  EOT
  default     = null
}

variable "cdc_password_parameter" {
  type        = string
  description = "Name of the SSM parameter holding the CDC password. Set or null together with the username."
  default     = null
}

variable "cdc_kms_key_id" {
  type        = string
  description = <<-EOT
    KMS key encrypting the CDC SecureString parameters (alias/id/ARN). Default
    alias/aws/ssm adds no kms:Decrypt. See module README.
  EOT
  default     = "alias/aws/ssm"
}

# ── Capture scope ──────────────────────────────────────────────────────────────

variable "tables" {
  type        = list(string)
  description = <<-EOT
    Fully-qualified tables to capture, joined into table.include.list.
    Empty (default) captures everything.
  EOT
  default     = []
  nullable    = false
}

# ── Engine ─────────────────────────────────────────────────────────────────────

variable "engine" {
  type        = string
  description = "Source engine (mariadb or oracle)."
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

# ── Connector configuration (passthrough) ──────────────────────────────────────

variable "connector_config_file" {
  type        = string
  description = <<-EOT
    YAML or JSON file of connector properties, relative to the project
    directory (deliver it with an overlay). Use this OR
    connector_config_overrides, not both. See README.
  EOT
  default     = null

  validation {
    condition = (
      var.connector_config_file == null || var.connector_config_file == "" ||
      try(alltrue([
        for v in values(yamldecode(file("${path.module}/../${var.connector_config_file}"))) : v == null || can(tostring(v))
      ]), false)
    )
    error_message = "connector_config_file must name a readable YAML or JSON file, relative to the project directory, that decodes to a flat map of scalar values (use {} for an empty file)."
  }
}

variable "connector_config_overrides" {
  type        = map(string)
  description = <<-EOT
    Connector properties merged last; null removes a key. Use this OR
    connector_config_file, not both. In HCL write $$${...}. See README.
  EOT
  default     = {}
  nullable    = false
}

variable "worker_config_file" {
  type        = string
  description = <<-EOT
    YAML or JSON file of worker properties, relative to the project directory.
    Use this OR worker_config_overrides, not both. See README.
  EOT
  default     = null

  validation {
    condition = (
      var.worker_config_file == null || var.worker_config_file == "" ||
      try(alltrue([
        for v in values(yamldecode(file("${path.module}/../${var.worker_config_file}"))) : v == null || can(tostring(v))
      ]), false)
    )
    error_message = "worker_config_file must name a readable YAML or JSON file, relative to the project directory, that decodes to a flat map of scalar values (use {} for an empty file)."
  }

  validation {
    condition     = var.worker_config_file == null || var.worker_config_file == "" || var.worker_configuration_arn == null
    error_message = "worker_config_file has no effect with an external worker_configuration_arn; configure that worker configuration directly."
  }
}

variable "worker_config_overrides" {
  type        = map(string)
  description = <<-EOT
    Worker properties merged over the module defaults; null removes a key.
    Use this OR worker_config_file, not both. See README.
  EOT
  default     = {}
  nullable    = false
}

variable "mcu_count" {
  type        = number
  description = "MCUs per connector worker: 1, 2, 4 or 8."
  default     = 1
}

# ── Additional IAM ─────────────────────────────────────────────────────────────

variable "service_execution_role_arn" {
  type        = string
  description = <<-EOT
    Existing service execution role. When set, no IAM is created; apply the
    required_policy_json output to it. See module README.
  EOT
  default     = null
}

variable "additional_policy" {
  type        = any
  description = <<-EOT
    Extra IAM policy for the connector role: a JSON string, or the native
    object a {...} pipeline literal decodes to. See README.
  EOT
  default     = null
}

variable "additional_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs attached to the connector role."
  default     = []
  nullable    = false
}

# ── Logging & alarm (passthrough) ──────────────────────────────────────────────

variable "create_log_group" {
  type        = bool
  description = "Create the connector log group; requires log_delivery.cloudwatch_logs = {}."
  default     = false
  nullable    = false
}

variable "log_delivery" {
  type = object({
    cloudwatch_logs = optional(object({
      log_group = optional(string)
    }))
    s3 = optional(object({
      bucket = string
      prefix = optional(string)
    }))
    firehose = optional(object({
      delivery_stream = string
    }))
  })
  description = <<-EOT
    Worker log destinations. Null (default) delivers no logs: failures are very
    hard to debug. Needs log-delivery permissions on the deploy role. See README.
  EOT
  default     = null
}

variable "log_retention_in_days" {
  type        = number
  description = "Retention for the created log group (only with create_log_group)."
  default     = 30
}

variable "create_alarm" {
  type        = bool
  description = "Create the connector not-running CloudWatch alarm."
  default     = false
  nullable    = false
}

variable "alarm_actions" {
  type        = list(string)
  description = "Actions for the not-running alarm (e.g. SNS topic ARNs). Only with create_alarm."
  default     = []
  nullable    = false
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
