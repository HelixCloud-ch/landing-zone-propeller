# EKS Fargate native log router — aws-observability namespace + aws-logging ConfigMap.
#
# Amazon EKS on Fargate ships a built-in Fluent Bit process inside every micro-VM.
# You do not deploy a Fluent Bit pod; AWS runs it for you. The only required
# infrastructure is:
#   1. A Kubernetes namespace named exactly 'aws-observability' with the
#      'aws-observability: enabled' label.
#   2. A ConfigMap named exactly 'aws-logging' in that namespace containing
#      Fluent Bit filter/output/parser sections.
#
# The Fargate scheduler reads the ConfigMap before starting any Fargate pod and
# configures the log router accordingly. Changes only apply to new pods —
# existing pods must be restarted to pick up ConfigMap changes.
#
# IAM: the CloudWatch destination requires the pod execution role to have
# permissions to create and write the log group, because the built-in Fluent
# Bit log router runs under the Fargate pod execution role (not an IRSA role).
# When pod_execution_role_name is set, this module attaches those permissions.
#
# References:
#   https://docs.aws.amazon.com/eks/latest/userguide/fargate-logging.html

# ── aws-observability namespace ───────────────────────────────────────────────

resource "kubernetes_namespace_v1" "aws_observability" {
  metadata {
    name = "aws-observability"
    labels = {
      # Required label — without it Fargate does not activate the log router.
      "aws-observability" = "enabled"
    }
  }

  lifecycle {
    # Fargate creates this namespace implicitly in some cluster configurations;
    # ignore conflicts rather than failing the apply.
    ignore_changes = [metadata[0].annotations]
  }
}

# ── aws-logging ConfigMap ─────────────────────────────────────────────────────

resource "kubernetes_config_map_v1" "aws_logging" {
  metadata {
    name      = "aws-logging"
    namespace = kubernetes_namespace_v1.aws_observability.metadata[0].name
  }

  data = {
    # flb_log_cw controls whether the Fluent Bit process (internal) logs are
    # shipped to CloudWatch. Enable only for debugging — adds cost.
    flb_log_cw = tostring(var.ship_fluentbit_process_logs)

    # Kubernetes metadata enrichment: merges structured JSON log fields into
    # the log record and attaches pod/namespace/container metadata.
    # Kube_Meta_Cache_TTL: 300s reduces API-server pressure (default is 30m
    # which can cause stale metadata; 300s is a good middle ground).
    "filters.conf" = <<-FILTER
      [FILTER]
          Name             parser
          Match            *
          Key_name         log
          Parser           crio
      [FILTER]
          Name             kubernetes
          Match            kube.*
          Merge_Log        On
          Keep_Log         Off
          Buffer_Size      0
          Kube_Meta_Cache_TTL 300s
    FILTER

    "output.conf" = <<-OUTPUT
      [OUTPUT]
          Name                cloudwatch_logs
          Match               kube.*
          region              ${var.region}
          log_group_name      ${var.log_group_name}
          log_stream_prefix   ${var.log_stream_prefix}
          log_retention_days  ${var.log_retention_days}
          auto_create_group   true
    OUTPUT

    # crio parser handles the CRI-O / containerd log format used by EKS.
    "parsers.conf" = <<-PARSERS
      [PARSER]
          Name    crio
          Format  Regex
          Regex   ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>P|F) (?<log>.*)$
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z
    PARSERS
  }
}

# ── Pod execution role logging policy ─────────────────────────────────────────
#
# The Fargate native log router writes to CloudWatch under the pod execution
# role. Grant it the minimum permissions to create the log group/stream and put
# events, scoped to the configured log group. Attached only when a role name is
# supplied (always the case for the CloudWatch destination).

data "aws_caller_identity" "current" {
  count = var.pod_execution_role_name != null ? 1 : 0
}

resource "aws_iam_role_policy" "fargate_logging" {
  count = var.pod_execution_role_name != null ? 1 : 0

  name = "fargate-log-router-cloudwatch"
  role = var.pod_execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FargateLogRouterCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current[0].account_id}:log-group:${var.log_group_name}:*"
      }
    ]
  })
}
