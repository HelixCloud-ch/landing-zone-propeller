locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  create_role                 = var.service_execution_role_arn == null
  create_worker_configuration = var.worker_configuration_arn == null
  cdc_credentials_enabled     = var.cdc_username_parameter != null

  # The default AWS-managed SSM key (alias/aws/ssm) grants decrypt implicitly to
  # a principal already allowed ssm:GetParameter and cannot be named as an IAM
  # Resource; only a customer-managed key needs an explicit kms:Decrypt grant.
  kms_grant_needed = local.cdc_credentials_enabled && var.cdc_kms_key_id != "alias/aws/ssm"
  # With an external role nothing is looked up: a key ARN is used verbatim, an
  # alias/id leaves the KMS statement out of required_policy_json.
  kms_lookup                      = local.kms_grant_needed && local.create_role
  kms_key_id_is_arn               = can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/", var.cdc_kms_key_id))
  kms_decrypt_grant               = local.kms_lookup || (local.kms_grant_needed && local.kms_key_id_is_arn)
  kms_key_arn                     = local.kms_lookup ? data.aws_kms_key.cdc[0].arn : var.cdc_kms_key_id
  kafka_iam_enabled               = var.client_authentication == "IAM"
  kafka_iam_grants                = local.kafka_iam_enabled && var.kafka_cluster_arn != null
  connector_policy_has_statements = local.cdc_credentials_enabled || local.kafka_iam_grants

  # The connector ARN is not knowable before the connector is created, so the
  # service execution role's SourceArn condition matches any connector of this
  # name in this account/region.
  connector_arn_wildcard = "arn:${local.partition}:kafkaconnect:${var.region}:${local.account_id}:connector/${var.identifier}/*"

  service_execution_role_arn    = local.create_role ? aws_iam_role.connector[0].arn : var.service_execution_role_arn
  cloudwatch_log_group_name     = var.create_log_group ? aws_cloudwatch_log_group.connector[0].name : try(var.log_delivery.cloudwatch_logs.log_group, null)
  worker_configuration_arn      = local.create_worker_configuration ? aws_mskconnect_worker_configuration.this[0].arn : var.worker_configuration_arn
  worker_configuration_revision = local.create_worker_configuration ? aws_mskconnect_worker_configuration.this[0].latest_revision : var.worker_configuration_revision

  connector_class = {
    mariadb = "io.debezium.connector.mariadb.MariaDbConnector"
    oracle  = "io.debezium.connector.oracle.OracleConnector"
  }

  # Layer 1: opinionated defaults, per engine.
  common_connector_defaults = {
    "include.schema.changes"                                    = "false"
    "schema.history.internal.store.only.captured.tables.ddl"    = "true"
    "schema.history.internal.store.only.captured.databases.ddl" = "true"
    "snapshot.mode"                                             = "initial"
  }
  connector_defaults = {
    mariadb = local.common_connector_defaults
    oracle  = merge(local.common_connector_defaults, { "log.mining.strategy" = var.log_mining_strategy })
  }

  # Layer 2: values derived from typed inputs.
  engine_derived = {
    mariadb = { "database.server.id" = var.server_id }
    oracle = {
      "database.dbname"   = var.db_name
      "database.pdb.name" = var.pdb_name == "" ? null : var.pdb_name
    }
  }
  # Debezium's schema-history producer/consumer are plain Kafka clients and do
  # not inherit MSK Connect's cluster authentication.
  schema_history_client_auth = (
    var.client_authentication == "IAM" ? tomap({
      "security.protocol"                  = "SASL_SSL"
      "sasl.mechanism"                     = "AWS_MSK_IAM"
      "sasl.jaas.config"                   = "software.amazon.msk.auth.iam.IAMLoginModule required;"
      "sasl.client.callback.handler.class" = "software.amazon.msk.auth.iam.IAMClientCallbackHandler"
    }) :
    var.in_transit_encryption == "TLS" ? tomap({ "security.protocol" = "SSL" }) : tomap({})
  )
  schema_history_auth = merge([
    for role in ["producer", "consumer"] : {
      for k, v in local.schema_history_client_auth : "schema.history.internal.${role}.${k}" => v
    }
  ]...)
  connector_derived = merge(
    {
      "connector.class"                                 = local.connector_class[var.engine]
      "tasks.max"                                       = "1"
      "database.hostname"                               = var.db_host
      "database.port"                                   = tostring(var.db_port)
      "database.user"                                   = local.cdc_credentials_enabled ? "$${ssm::${var.cdc_username_parameter}}" : null
      "database.password"                               = local.cdc_credentials_enabled ? "$${ssm::${var.cdc_password_parameter}}" : null
      "topic.prefix"                                    = var.topic_prefix
      "schema.history.internal.kafka.bootstrap.servers" = var.bootstrap_servers
      "schema.history.internal.kafka.topic"             = var.schema_history_topic
      "config.action.reload"                            = "none"
      "table.include.list"                              = var.table_include_list == "" ? null : var.table_include_list
    },
    local.engine_derived[var.engine],
    local.schema_history_auth,
  )

  # Layer 3 wins; a null value at any layer removes the key.
  connector_configuration = {
    for k, v in merge(local.connector_defaults[var.engine], local.connector_derived, var.connector_config_overrides) :
    k => v if v != null
  }

  worker_defaults = {
    "key.converter"                     = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter"                   = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable"    = "false"
    "offset.storage.topic"              = var.offset_topic
    "config.providers"                  = "ssm"
    "config.providers.ssm.class"        = "com.amazonaws.kafka.config.providers.SsmParamStoreConfigProvider"
    "config.providers.ssm.param.region" = var.region
  }
  worker_properties = {
    for k, v in merge(local.worker_defaults, var.worker_config_overrides) : k => v if v != null
  }
  worker_properties_file_content = join("", [
    for k in sort(keys(local.worker_properties)) : "${k}=${local.worker_properties[k]}\n"
  ])
  # Worker configurations cannot be updated in place and inherit the
  # connector's create_before_destroy, so the name must change with content.
  worker_configuration_name = "${var.identifier}-worker-${substr(sha256(local.worker_properties_file_content), 0, 8)}"
}
