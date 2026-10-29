# Context data sources and the service execution role live in iam.tf; derived
# values live in locals.tf. This file holds the connector and its directly
# attached resources: security group, log group, worker configuration, the
# connector itself, and the not-running alarm. Every supporting resource is
# optional; see README "Bring your own resources".

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "connector" {
  # checkov:skip=CKV2_AWS_5: the group is attached to the connector ENIs via aws_mskconnect_connector.this kafka_cluster.vpc.security_groups; checkov cannot follow the reference once the group is counted.
  count = var.create_security_group ? 1 : 0

  name        = "${var.identifier}-connector"
  description = "MSK Connect Debezium connector ENIs for ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.identifier}-connector" })
}

resource "aws_vpc_security_group_egress_rule" "database" {
  count = var.create_security_group ? 1 : 0

  security_group_id = aws_security_group.connector[0].id
  from_port         = var.db_port
  to_port           = var.db_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Connector egress to the source database"
}

resource "aws_vpc_security_group_egress_rule" "brokers" {
  count = var.create_security_group ? 1 : 0

  security_group_id = aws_security_group.connector[0].id
  from_port         = var.broker_port
  to_port           = var.broker_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Connector egress to the Kafka brokers"
}

resource "aws_vpc_security_group_egress_rule" "additional" {
  for_each = var.create_security_group ? var.additional_egress_rules : {}

  security_group_id            = aws_security_group.connector[0].id
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.ip_protocol == "-1" ? null : coalesce(each.value.to_port, each.value.from_port)
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.referenced_security_group_id
  description                  = coalesce(each.value.description, "Connector egress: ${each.key}")
}

# ── Log Group ─────────────────────────────────────────────────────────────────

# Retention is a finite, consumer-overridable input (var.log_retention_in_days);
# no longer minimum is imposed on connector logs, which carry operational
# status only.
resource "aws_cloudwatch_log_group" "connector" {
  # checkov:skip=CKV_AWS_338: retention is a deliberate, finite, consumer-overridable input (var.log_retention_in_days); connector logs are operational, not audit data.
  # checkov:skip=CKV_AWS_158: connector logs carry operational status, not captured row data (that flows to Kafka topics); CloudWatch Logs encrypts at rest by default, and a customer-managed key would need a new key input plus a key-policy grant for the logs service. A consumer needing a CMK can bring its own log group via log_delivery.
  count = var.create_log_group ? 1 : 0

  name              = "/aws/mskconnect/${var.identifier}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

# ── Worker Configuration ──────────────────────────────────────────────────────

resource "aws_mskconnect_worker_configuration" "this" {
  count = local.create_worker_configuration ? 1 : 0

  name        = local.worker_configuration_name
  description = "Worker configuration for the ${var.identifier} Debezium connector"

  properties_file_content = local.worker_properties_file_content

  lifecycle {
    create_before_destroy = true
  }
}

# ── Connector ─────────────────────────────────────────────────────────────────

resource "aws_mskconnect_connector" "this" {
  name                 = var.identifier
  kafkaconnect_version = var.kafkaconnect_version

  capacity {
    provisioned_capacity {
      mcu_count    = var.mcu_count
      worker_count = 1
    }
  }

  connector_configuration = local.connector_configuration

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = var.bootstrap_servers

      vpc {
        security_groups = concat(aws_security_group.connector[*].id, var.security_group_ids)
        subnets         = var.subnet_ids
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = var.client_authentication
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = var.in_transit_encryption
  }

  plugin {
    custom_plugin {
      # Changing custom_plugin_arn (a new Debezium version) forces replacement:
      # MSK Connect connectors are immutable with respect to their plugin.
      arn      = var.custom_plugin_arn
      revision = var.custom_plugin_revision
    }
  }

  worker_configuration {
    arn      = local.worker_configuration_arn
    revision = local.worker_configuration_revision
  }

  dynamic "log_delivery" {
    for_each = var.log_delivery == null ? [] : [var.log_delivery]
    content {
      worker_log_delivery {
        dynamic "cloudwatch_logs" {
          for_each = log_delivery.value.cloudwatch_logs == null ? [] : [1]
          content {
            enabled   = true
            log_group = local.cloudwatch_log_group_name
          }
        }

        dynamic "s3" {
          for_each = log_delivery.value.s3 == null ? [] : [log_delivery.value.s3]
          content {
            enabled = true
            bucket  = s3.value.bucket
            prefix  = s3.value.prefix
          }
        }

        dynamic "firehose" {
          for_each = log_delivery.value.firehose == null ? [] : [log_delivery.value.firehose]
          content {
            enabled         = true
            delivery_stream = firehose.value.delivery_stream
          }
        }
      }
    }
  }

  service_execution_role_arn = local.service_execution_role_arn

  tags = var.tags

  # The connector reads SSM/Kafka with these grants at start; referencing only
  # the role ARN would let the policies attach after the create call. The log
  # group must exist before log delivery to it is configured.
  depends_on = [
    aws_iam_role_policy.connector,
    aws_iam_role_policy.additional,
    aws_iam_role_policy_attachment.additional,
    aws_cloudwatch_log_group.connector,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ── Alarm ─────────────────────────────────────────────────────────────────────

# alarm_actions defaults to [] because notification targets are
# consumer-specific; supply them when create_alarm is enabled.
resource "aws_cloudwatch_metric_alarm" "not_running" {
  count = var.create_alarm ? 1 : 0

  alarm_name          = "${var.identifier}-connector-not-running"
  alarm_description   = "Fires when the ${var.identifier} MSK Connect connector is not in a running state."
  namespace           = "AWS/KafkaConnect"
  metric_name         = "ConnectorRunningTaskCount"
  dimensions          = { "Connector Name" = aws_mskconnect_connector.this.name }
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "breaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = var.tags
}
