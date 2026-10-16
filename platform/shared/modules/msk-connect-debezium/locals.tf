locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # The default AWS-managed SSM key (alias/aws/ssm) grants decrypt implicitly to
  # a principal already allowed ssm:GetParameter and cannot be named as an IAM
  # Resource; only a customer-managed key needs an explicit kms:Decrypt grant.
  cdc_kms_is_customer_managed = var.cdc_kms_key_id != "alias/aws/ssm"

  # The connector ARN is not knowable before the connector is created, so the
  # service execution role's SourceArn condition matches any connector of this
  # name in this account/region. See the checkov:skip on the assume-role policy.
  connector_arn_wildcard = "arn:${local.partition}:kafkaconnect:${var.region}:${local.account_id}:connector/${var.identifier}/*"

  # Kafka data-plane permissions are only meaningful under IAM auth; with NONE
  # the connector authenticates at the transport layer and needs none.
  kafka_iam_enabled = var.client_authentication == "IAM"

  # Path to the per-engine connector configuration template. The file itself is
  # added per engine (mariadb in task 1.19, oracle in Phase 2).
  config_template = "${path.module}/config/${var.engine}.tftpl"

  # aws_mskconnect_connector.connector_configuration is a map(string). The
  # engine templates are authored as a Kafka Connect properties body (key=value
  # lines) so they stay readable and match Debezium's own documentation, then
  # are decoded here into the map the resource requires. Blank lines — which the
  # %{ if }/%{ endif } directive can leave when table.include.list is omitted —
  # are dropped, and each line is split on its first "=" only (Debezium values
  # may themselves contain "=").
  rendered_config = templatefile(local.config_template, {
    db_host                = var.db_host
    db_port                = var.db_port
    db_name                = var.db_name
    pdb_name               = var.pdb_name
    server_id              = var.server_id
    topic_prefix           = var.topic_prefix
    bootstrap_servers      = var.bootstrap_servers
    schema_history_topic   = var.schema_history_topic
    cdc_username_parameter = var.cdc_username_parameter
    cdc_password_parameter = var.cdc_password_parameter
    table_include_list     = var.table_include_list
    log_mining_strategy    = var.log_mining_strategy
  })

  connector_configuration = {
    for line in compact(split("\n", local.rendered_config)) :
    trimspace(regex("^[^=]+", line)) => trimspace(regex("=(.*)$", line)[0])
    if trimspace(line) != ""
  }
}
