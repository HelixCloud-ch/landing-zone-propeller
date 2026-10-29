# Identity used only to construct the credential parameters' ARNs from their
# names — no secret is read. Reading the parameters' *values* with an
# aws_ssm_parameter data source would pull the decrypted SecureString into
# Terraform state, which is exactly what the SSM config provider design avoids
# (see the module README). An SSM parameter ARN is fully determined by
# partition + region + account + name, so it is composed here instead.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # Compose each credential parameter's ARN from its name, only when the name
  # is set. SSM parameter names may be given with or without a leading "/"; the
  # ARN form always carries a single "/" after "parameter", so the leading slash
  # is trimmed before it is re-added.
  cdc_username_parameter_arn = var.cdc_username_parameter == null ? null : "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.cdc_username_parameter, "/")}"
  cdc_password_parameter_arn = var.cdc_password_parameter == null ? null : "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.cdc_password_parameter, "/")}"

  # Select the plugin ARN/revision from the maps published by msk-connect-plugin.
  # The pipeline cannot pick a map key (a propeller input reads a whole field),
  # so the selection is done here: pin "<engine>-<plugin_version>" out of the
  # version-keyed maps when plugin_version is set, else the flavour's default
  # out of the flavour-keyed maps. The plugin_version validation guarantees the
  # chosen key exists, so these lookups never fail at plan time.
  selected_plugin_arn = (
    var.plugin_version == ""
    ? var.default_plugin_arns[var.engine]
    : var.plugin_arns["${var.engine}-${var.plugin_version}"]
  )
  selected_plugin_revision = (
    var.plugin_version == ""
    ? var.default_plugin_revisions[var.engine]
    : var.plugin_revisions["${var.engine}-${var.plugin_version}"]
  )

  table_include_list = join(",", var.tables)

  # A {...} pipeline literal reaches Terraform as a native object
  # (_propeller-vars), while HCL tfvars usually pass a JSON string.
  additional_policy_json = var.additional_policy == null ? null : try(tostring(var.additional_policy), jsonencode(var.additional_policy))

  # Config files are relative to the project directory (terraform runs in
  # <project>/terraform). YAML numbers/bools become strings; a null value is
  # kept so it removes the key in the module. A missing path yields {}; a bad
  # file is already rejected by the variable validation.
  connector_config_from_file = try({
    for k, v in yamldecode(file("${path.module}/../${var.connector_config_file}")) : k => v == null ? null : tostring(v)
  }, {})
  worker_config_from_file = try({
    for k, v in yamldecode(file("${path.module}/../${var.worker_config_file}")) : k => v == null ? null : tostring(v)
  }, {})

  # File first, inline map on top: the inline value wins on overlapping keys.
  connector_config_overrides = merge(local.connector_config_from_file, var.connector_config_overrides)
  worker_config_overrides    = merge(local.worker_config_from_file, var.worker_config_overrides)

  connector_config_overlap = sort(tolist(setintersection(keys(local.connector_config_from_file), keys(var.connector_config_overrides))))
  worker_config_overlap    = sort(tolist(setintersection(keys(local.worker_config_from_file), keys(var.worker_config_overrides))))

  # Derive a deterministic MariaDB database.server.id from the identifier when
  # the consumer does not supply one. MariaDB server-id is a 32-bit value in
  # 1..4294967295; take the top 32 bits of the identifier's SHA-256 and fold
  # into 1..4294967295 so it is stable per identifier and never 0.
  server_id = coalesce(
    var.server_id,
    tostring((parseint(substr(sha256(var.identifier), 0, 8), 16) % 4294967295) + 1),
  )
}

# Using both a config file and the inline map is allowed but discouraged. A
# failed check assertion is reported as a plan warning and never fails the run.
check "connector_config_sources" {
  assert {
    condition     = length(local.connector_config_from_file) == 0 || length(var.connector_config_overrides) == 0
    error_message = "connector_config_file and connector_config_overrides are both set; the inline map wins on overlapping keys: ${length(local.connector_config_overlap) == 0 ? "(none)" : join(", ", local.connector_config_overlap)}. Using only one source is strongly recommended."
  }
}

check "worker_config_sources" {
  assert {
    condition     = length(local.worker_config_from_file) == 0 || length(var.worker_config_overrides) == 0
    error_message = "worker_config_file and worker_config_overrides are both set; the inline map wins on overlapping keys: ${length(local.worker_config_overlap) == 0 ? "(none)" : join(", ", local.worker_config_overlap)}. Using only one source is strongly recommended."
  }
}

module "debezium" {
  source = "../../../shared/modules/msk-connect-debezium"

  # Identity
  identifier = var.identifier
  region     = var.region
  tags       = merge(var.tags, var.consumer_tags, var.propeller_tags)

  # Network
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
  db_host    = var.db_host
  db_port    = var.db_port
  db_name    = var.db_name
  pdb_name   = var.pdb_name

  create_security_group   = var.create_security_group
  security_group_ids      = var.security_group_ids
  additional_egress_rules = var.additional_egress_rules

  # Kafka
  bootstrap_servers     = var.bootstrap_servers
  broker_port           = var.broker_port
  kafka_cluster_arn     = var.kafka_cluster_arn
  client_authentication = var.client_authentication
  in_transit_encryption = var.in_transit_encryption

  # Plugin (selected from the maps by engine + optional plugin_version above)
  custom_plugin_arn      = local.selected_plugin_arn
  custom_plugin_revision = local.selected_plugin_revision

  # Worker configuration / topics
  worker_configuration_arn      = var.worker_configuration_arn
  worker_configuration_revision = var.worker_configuration_revision
  offset_topic                  = var.offset_topic
  schema_history_topic          = var.schema_history_topic
  topic_prefix                  = var.topic_prefix
  server_id                     = local.server_id

  # Credentials: the two parameter names come straight from inputs; their ARNs
  # are composed from account/region/partition (see locals above).
  cdc_username_parameter     = var.cdc_username_parameter
  cdc_password_parameter     = var.cdc_password_parameter
  cdc_username_parameter_arn = local.cdc_username_parameter_arn
  cdc_password_parameter_arn = local.cdc_password_parameter_arn
  cdc_kms_key_id             = var.cdc_kms_key_id

  # Capture scope
  table_include_list = local.table_include_list

  # Engine
  engine              = var.engine
  log_mining_strategy = var.log_mining_strategy

  # Connector configuration (file + inline map, merged above)
  connector_config_overrides = local.connector_config_overrides
  worker_config_overrides    = local.worker_config_overrides
  mcu_count                  = var.mcu_count

  # IAM
  service_execution_role_arn = var.service_execution_role_arn
  additional_policy_json     = local.additional_policy_json
  additional_policy_arns     = var.additional_policy_arns

  # Logging & alarm
  create_log_group      = var.create_log_group
  log_delivery          = var.log_delivery
  log_retention_in_days = var.log_retention_in_days
  create_alarm          = var.create_alarm
  alarm_actions         = var.alarm_actions
}
