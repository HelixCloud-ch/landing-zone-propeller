# Context data sources and the service execution role live in iam.tf; derived
# values live in locals.tf. This file holds the connector and its directly
# attached resources: security group, log group, worker configuration, the
# connector itself, and the not-running alarm.

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "connector" {
  name        = "${var.identifier}-connector"
  description = "MSK Connect Debezium connector ENIs for ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.identifier}-connector" })
}

resource "aws_vpc_security_group_egress_rule" "database" {
  security_group_id = aws_security_group.connector.id
  from_port         = var.db_port
  to_port           = var.db_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Connector egress to the source database"
}

resource "aws_vpc_security_group_egress_rule" "brokers" {
  security_group_id = aws_security_group.connector.id
  from_port         = var.broker_port
  to_port           = var.broker_port
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Connector egress to the Kafka brokers"
}

# ── Log Group ─────────────────────────────────────────────────────────────────

# Retention is an explicit, finite, consumer-overridable input
# (var.log_retention_in_days); a longer minimum is deliberately not imposed on
# connector logs. This mirrors ADR-019's already-accepted CKV_AWS_338 on the
# MSK cluster's own log group — accepted, not fixed, in task 1.27.
resource "aws_cloudwatch_log_group" "connector" {
  # checkov:skip=CKV_AWS_338: finite retention is a deliberate, overridable default (var.log_retention_in_days); see comment above and ADR-019.
  # checkov:skip=CKV_AWS_158: connector logs carry operational status, not captured row data (that flows to Kafka topics); KMS-encrypting this log group would require a new key input and a CloudWatch Logs key-policy grant, out of scope for Phase 1. Flag for Review Gate 2.
  name              = "/aws/mskconnect/${var.identifier}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

# ── Worker Configuration ──────────────────────────────────────────────────────

resource "aws_mskconnect_worker_configuration" "this" {
  name        = "${var.identifier}-worker"
  description = "Worker configuration for the ${var.identifier} Debezium connector"

  properties_file_content = <<-EOT
    key.converter=org.apache.kafka.connect.storage.StringConverter
    value.converter=org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable=false
    offset.storage.topic=${var.offset_topic}
    config.providers=ssm
    config.providers.ssm.class=com.amazonaws.kafka.config.providers.SsmParamStoreConfigProvider
    config.providers.ssm.param.region=${var.region}
  EOT
}

# ── Connector ─────────────────────────────────────────────────────────────────

resource "aws_mskconnect_connector" "this" {
  name                 = var.identifier
  kafkaconnect_version = var.kafkaconnect_version

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = 1
    }
  }

  connector_configuration = local.connector_configuration

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = var.bootstrap_servers

      vpc {
        security_groups = [aws_security_group.connector.id]
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
    arn      = aws_mskconnect_worker_configuration.this.arn
    revision = aws_mskconnect_worker_configuration.this.latest_revision
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.connector.name
      }
    }
  }

  service_execution_role_arn = aws_iam_role.connector.arn

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ── Alarm ─────────────────────────────────────────────────────────────────────

# alarm_actions defaults to [] because the framework has no notification-target
# convention yet; a consumer supplies actions once one exists. If checkov flags
# the empty actions list in task 1.27, it is an accepted finding for this
# reason, not a fix.
resource "aws_cloudwatch_metric_alarm" "not_running" {
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
