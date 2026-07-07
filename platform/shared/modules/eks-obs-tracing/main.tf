# EKS observability — tracing backend (Transaction Search).
#
# Transaction Search is the 2026 forward path for distributed tracing on AWS.
# The X-Ray SDK/Daemon entered maintenance mode on 2026-02-25; new builds should
# instrument with OpenTelemetry SDKs and send spans to this backend.
#
# This module configures the account/region-scoped backend — NOT per-cluster.
# All workloads in the account that send traces to X-Ray will have their spans
# routed to CloudWatch Logs once this is enabled.
#
# What it sets up:
#   1. aws_xray_trace_segment_destination → "CloudWatchLogs"
#      Routes all X-Ray PutTraceSegments calls to CloudWatch instead of the
#      legacy X-Ray store.
#   2. aws_xray_indexing_rule ("Default")
#      Controls what percentage of trace IDs are indexed as trace summaries for
#      analytics. The rest are still stored in aws/spans but not individually
#      searchable. AWS provides 1% free.
#   3. aws_cloudwatch_log_resource_policy
#      Grants xray.amazonaws.com permission to write to the aws/spans and
#      /aws/application-signals/data log groups. Required for API-based
#      enablement (the console sets this policy automatically).
#
# Terraform note: removing aws_xray_trace_segment_destination or
# aws_xray_indexing_rule from state has no effect on the underlying AWS
# configuration — those resources are idempotent PUT operations, not create/
# delete lifecycle resources.
#
# References:
#   https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search.html
#   https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Enable-TransactionSearch.html
#   https://docs.aws.amazon.com/xray/latest/api/API_UpdateTraceSegmentDestination.html
#   https://docs.aws.amazon.com/xray/latest/api/API_UpdateIndexingRule.html

# ── X-Ray trace segment destination ──────────────────────────────────────────

resource "aws_xray_trace_segment_destination" "this" {
  count = var.enable_transaction_search ? 1 : 0

  destination = "CloudWatchLogs"
}

# ── Indexing rule (trace summary sampling %) ──────────────────────────────────

resource "aws_xray_indexing_rule" "default" {
  count = var.enable_transaction_search ? 1 : 0

  name = "Default"

  rule {
    probabilistic {
      desired_sampling_percentage = var.spans_indexing_sampling_percentage
    }
  }
}

# ── Resource-based policy: allow X-Ray to write to CloudWatch Logs ────────────
#
# Required when enabling via API (the CloudWatch console configures this
# automatically). Without this policy X-Ray cannot write to aws/spans and
# the spans will fail to land.
#
# The account ID is resolved at plan time from the AWS provider credentials via
# data.aws_caller_identity — no need to pass it as a variable.

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_resource_policy" "xray_spans" {
  count = var.enable_transaction_search ? 1 : 0

  policy_name = "xray-transaction-search-${var.region}"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TransactionSearchXRayAccess"
        Effect = "Allow"
        Principal = {
          Service = "xray.amazonaws.com"
        }
        Action = "logs:PutLogEvents"
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:aws/spans:*",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/application-signals/data:*",
        ]
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:xray:${var.region}:${data.aws_caller_identity.current.account_id}:*"
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
