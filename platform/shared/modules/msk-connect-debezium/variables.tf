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
  description = "AWS region as a literal, used for the ssm config provider in the created worker configuration."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources that take a tags map. The project passes the merged tag set; the module does not know propeller's tag triple."
  default     = {}
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "create_security_group" {
  type        = bool
  description = "Create the connector security group (with database and broker egress rules)."
  default     = true
  nullable    = false
}

variable "security_group_ids" {
  type        = list(string)
  description = <<-EOT
    Existing security groups for the connector ENIs, added to the created one
    (if any). At least one SG overall. Changing the set replaces the connector.
  EOT
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "All security_group_ids must be valid security group IDs (e.g. sg-0123456789abcdef0)."
  }

  validation {
    condition     = var.create_security_group || length(var.security_group_ids) > 0
    error_message = "With create_security_group = false, security_group_ids must name at least one security group."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the created security group. Required only when create_security_group is true."
  default     = null

  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }

  validation {
    condition     = !var.create_security_group || var.vpc_id != null
    error_message = "vpc_id is required when create_security_group is true."
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
  description = "Port of the source database. Opened as egress on the created security group."
  default     = 3306

  validation {
    condition     = var.db_port >= 1 && var.db_port <= 65535
    error_message = "db_port must be between 1 and 65535."
  }
}

variable "db_name" {
  type        = string
  description = <<-EOT
    Oracle service name / SID (database.dbname). Ignored for mariadb.
    On a CDB source this is the container's service; see pdb_name.
  EOT
  default     = ""
}

variable "pdb_name" {
  type        = string
  description = <<-EOT
    Oracle pluggable database (database.pdb.name) for a CDB source.
    Empty (default) omits the property. Ignored for mariadb.
  EOT
  default     = ""
}

variable "broker_port" {
  type        = number
  description = "Kafka broker port. Opened as egress on the created security group."
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
  description = <<-EOT
    Extra egress rules on the created security group, keyed by a stable name.
    Each sets exactly one destination; to_port defaults to from_port.
  EOT
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for r in values(var.additional_egress_rules) :
      length([for d in [r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_id] : d if d != null]) == 1
    ])
    error_message = "Each additional_egress_rules entry must set exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id."
  }

  validation {
    condition     = var.create_security_group || length(var.additional_egress_rules) == 0
    error_message = "additional_egress_rules apply only to the module-created security group; they have no effect with create_security_group = false."
  }
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

variable "worker_configuration_arn" {
  type        = string
  description = "Existing MSK Connect worker configuration to use instead of creating one. See README."
  default     = null

  validation {
    condition     = var.worker_configuration_arn == null || can(regex("^arn:aws[a-z-]*:kafkaconnect:", var.worker_configuration_arn))
    error_message = "worker_configuration_arn must be an MSK Connect worker configuration ARN (arn:aws:kafkaconnect:...)."
  }
}

variable "worker_configuration_revision" {
  type        = number
  description = "Revision of worker_configuration_arn. Set both or neither."
  default     = null

  validation {
    condition     = (var.worker_configuration_revision == null) == (var.worker_configuration_arn == null)
    error_message = "worker_configuration_arn and worker_configuration_revision must be set together."
  }
}

variable "offset_topic" {
  type        = string
  description = <<-EOT
    Kafka topic for source offsets, declared in the created worker
    configuration. Required unless worker_configuration_arn is set.
  EOT
  default     = null

  validation {
    condition     = var.offset_topic != null || var.worker_configuration_arn != null
    error_message = "offset_topic is required when the module creates the worker configuration (worker_configuration_arn unset)."
  }
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
  description = <<-EOT
    SSM parameter holding the CDC user name, referenced via the ssm config
    provider. Null (with the password) derives no credentials. See README.
  EOT
  default     = null

  validation {
    condition     = (var.cdc_username_parameter == null) == (var.cdc_password_parameter == null)
    error_message = "cdc_username_parameter and cdc_password_parameter must be set together or both left null."
  }
}

variable "cdc_password_parameter" {
  type        = string
  description = "SSM parameter holding the CDC user password. Set or null together with the username."
  default     = null
}

variable "cdc_username_parameter_arn" {
  type        = string
  description = "ARN of cdc_username_parameter; scopes ssm:GetParameter. Set exactly when the name is set."
  default     = null

  validation {
    condition     = var.cdc_username_parameter_arn == null || can(regex("^arn:aws[a-z-]*:ssm:", var.cdc_username_parameter_arn))
    error_message = "cdc_username_parameter_arn must be a valid SSM parameter ARN (arn:aws:ssm:...)."
  }

  validation {
    condition     = (var.cdc_username_parameter_arn == null) == (var.cdc_username_parameter == null)
    error_message = "cdc_username_parameter_arn must be set exactly when cdc_username_parameter is set."
  }
}

variable "cdc_password_parameter_arn" {
  type        = string
  description = "ARN of cdc_password_parameter; scopes ssm:GetParameter. Set exactly when the name is set."
  default     = null

  validation {
    condition     = var.cdc_password_parameter_arn == null || can(regex("^arn:aws[a-z-]*:ssm:", var.cdc_password_parameter_arn))
    error_message = "cdc_password_parameter_arn must be a valid SSM parameter ARN (arn:aws:ssm:...)."
  }

  validation {
    condition     = (var.cdc_password_parameter_arn == null) == (var.cdc_password_parameter == null)
    error_message = "cdc_password_parameter_arn must be set exactly when cdc_password_parameter is set."
  }
}

variable "cdc_kms_key_id" {
  type        = string
  description = <<-EOT
    KMS key (alias, id or ARN) encrypting the CDC SecureString parameters.
    alias/aws/ssm (default) adds no kms:Decrypt. Ignored when credentials are
    null. See README.
  EOT
  default     = "alias/aws/ssm"
}

# ── Kafka authentication ──────────────────────────────────────────────────────

variable "kafka_cluster_arn" {
  type        = string
  description = <<-EOT
    ARN of the target MSK cluster; scopes the kafka-cluster:* grants. Required
    only for IAM auth when the module creates the role.
  EOT
  default     = null

  validation {
    condition     = var.kafka_cluster_arn == null || can(regex("^arn:aws[a-z-]*:kafka:", var.kafka_cluster_arn))
    error_message = "kafka_cluster_arn must be a valid MSK cluster ARN (arn:aws:kafka:...)."
  }

  validation {
    condition     = var.kafka_cluster_arn != null || var.client_authentication != "IAM" || var.service_execution_role_arn != null
    error_message = "kafka_cluster_arn is required when client_authentication is IAM and the module creates the service execution role."
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
  description = "Comma-separated table.include.list. Empty (default) omits the property and captures everything."
  default     = ""
}

# ── Engine ────────────────────────────────────────────────────────────────────

variable "engine" {
  type        = string
  description = "Source engine. Selects the connector class and the per-engine defaults."
  default     = "mariadb"

  validation {
    condition     = contains(["mariadb", "oracle"], var.engine)
    error_message = "engine must be 'mariadb' or 'oracle'."
  }
}

variable "log_mining_strategy" {
  type        = string
  description = <<-EOT
    Oracle log.mining.strategy, set in the defaults layer (overridable).
    Ignored for mariadb. See README for hybrid vs online_catalog.
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

# ── Connector configuration ───────────────────────────────────────────────────

variable "connector_config_overrides" {
  type        = map(string)
  description = <<-EOT
    Connector properties merged last, over the module defaults and the
    derived values; a null value removes the key. Unrestricted: see README.
  EOT
  default     = {}
  nullable    = false
}

variable "worker_config_overrides" {
  type        = map(string)
  description = "Worker properties merged over the module defaults; null removes a key. See README."
  default     = {}
  nullable    = false

  validation {
    condition     = var.worker_configuration_arn == null || length(var.worker_config_overrides) == 0
    error_message = "worker_config_overrides has no effect with an external worker_configuration_arn; configure that worker configuration directly."
  }
}

# ── Capacity ──────────────────────────────────────────────────────────────────

variable "mcu_count" {
  type        = number
  description = "MCUs per worker (1, 2, 4 or 8). worker_count stays 1: Debezium runs a single task."
  default     = 1

  validation {
    condition     = contains([1, 2, 4, 8], var.mcu_count)
    error_message = "mcu_count must be 1, 2, 4 or 8."
  }
}

# ── IAM ───────────────────────────────────────────────────────────────────────

variable "service_execution_role_arn" {
  type        = string
  description = <<-EOT
    Existing service execution role for the connector. When set, the module
    creates no role or policies; apply required_policy_json to it. See README.
  EOT
  default     = null

  validation {
    condition     = var.service_execution_role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.service_execution_role_arn))
    error_message = "service_execution_role_arn must be an IAM role ARN (arn:aws:iam::<account-id>:role/...)."
  }
}

variable "additional_policy_json" {
  type        = string
  description = <<-EOT
    Extra IAM policy document (JSON) attached inline to the created role, for
    resources that overrides reference. Not allowed with an external role.
  EOT
  default     = null

  validation {
    condition     = var.additional_policy_json == null || can(jsondecode(var.additional_policy_json))
    error_message = "additional_policy_json must be a valid JSON policy document."
  }

  validation {
    condition     = var.additional_policy_json == null || var.service_execution_role_arn == null
    error_message = "additional_policy_json cannot be used with service_execution_role_arn; grant the permissions on the external role instead."
  }
}

variable "additional_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs (known at plan time) for the created role. Not allowed with an external role."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.additional_policy_arns : can(regex("^arn:aws[a-z-]*:iam::", a))])
    error_message = "additional_policy_arns must be IAM policy ARNs (arn:aws:iam::...)."
  }

  validation {
    condition     = length(var.additional_policy_arns) == 0 || var.service_execution_role_arn == null
    error_message = "additional_policy_arns cannot be used with service_execution_role_arn; attach the policies to the external role instead."
  }
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "create_log_group" {
  type        = bool
  description = <<-EOT
    Create the /aws/mskconnect/<identifier> log group and deliver to it.
    Requires log_delivery.cloudwatch_logs without log_group. See README.
  EOT
  default     = false
  nullable    = false

  validation {
    condition = !var.create_log_group || (
      try(var.log_delivery.cloudwatch_logs, null) != null &&
      try(var.log_delivery.cloudwatch_logs.log_group, null) == null
    )
    error_message = "create_log_group = true requires log_delivery.cloudwatch_logs = {} (log_group unset: the created group is used)."
  }

  validation {
    condition = (
      var.create_log_group ||
      try(var.log_delivery.cloudwatch_logs, null) == null ||
      try(var.log_delivery.cloudwatch_logs.log_group, null) != null
    )
    error_message = "log_delivery.cloudwatch_logs needs log_group, or create_log_group = true to use the module-created group."
  }
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
    Worker log destinations (cloudwatch_logs, s3, firehose). Null (default)
    delivers no logs, which makes failures very hard to debug. See README.
  EOT
  default     = null

  validation {
    condition = var.log_delivery == null || anytrue([
      for d in ["cloudwatch_logs", "s3", "firehose"] : try(var.log_delivery[d], null) != null
    ])
    error_message = "log_delivery must set at least one of cloudwatch_logs, s3, firehose (or be null)."
  }
}

variable "log_retention_in_days" {
  type        = number
  description = "Retention for the created log group (used only with create_log_group)."
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values CloudWatch Logs accepts (e.g. 1, 7, 30, 90, 365, 0 for never expire)."
  }
}

# ── Alarm ─────────────────────────────────────────────────────────────────────

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

  validation {
    condition     = var.create_alarm || length(var.alarm_actions) == 0
    error_message = "alarm_actions has no effect with create_alarm = false."
  }
}
