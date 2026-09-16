# Identity used only to construct the credential parameters' ARNs from their
# names — no secret is read. Reading the parameters' *values* with an
# aws_ssm_parameter data source would pull the decrypted SecureString into
# Terraform state, which is exactly what the SSM Config Provider design avoids
# (see the module README and ADR-020). An SSM parameter ARN is fully determined
# by partition + region + account + name, so it is composed here instead.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # Compose each credential parameter's ARN from its name. SSM parameter names
  # may be given with or without a leading "/"; the ARN form always carries a
  # single "/" after "parameter", so the leading slash is trimmed before it is
  # re-added. Passed to the module, which scopes ssm:GetParameter to exactly
  # these ARNs.
  cdc_username_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.cdc_username_parameter, "/")}"
  cdc_password_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.cdc_password_parameter, "/")}"

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

  # Decode the tables list and build the module's comma-separated
  # table.include.list. An empty list captures everything, expressed as "" —
  # the module's template then omits the property entirely.
  tables             = jsondecode(var.tables)
  table_include_list = length(local.tables) > 0 ? join(",", local.tables) : ""

  # Derive a deterministic MariaDB database.server.id from the identifier when
  # the consumer does not supply one (Req 5.12). MariaDB server-id is a 32-bit
  # value in 1..4294967295; take the top 32 bits of the identifier's SHA-256 and
  # fold into 1..4294967295 so it is stable per identifier and never 0.
  server_id = coalesce(
    var.server_id,
    tostring((parseint(substr(sha256(var.identifier), 0, 8), 16) % 4294967295) + 1),
  )
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
  offset_topic         = var.offset_topic
  schema_history_topic = var.schema_history_topic
  topic_prefix         = var.topic_prefix
  server_id            = local.server_id

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

  # Logging & alarm
  log_retention_in_days = var.log_retention_in_days
  alarm_actions         = var.alarm_actions
}
