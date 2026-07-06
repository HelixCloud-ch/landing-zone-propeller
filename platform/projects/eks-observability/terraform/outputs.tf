# ── Fargate log router ─────────────────────────────────────────────────────────

output "fargate_log_group_name" {
  description = "CloudWatch Logs log group for container application logs. Null when install_fargate_logs = false."
  value       = one(module.fargate_logs[*].log_group_name)
}

# ── Fargate ADOT metrics collector ────────────────────────────────────────────

output "adot_collector_role_arn" {
  description = "ARN of the IRSA role for the ADOT Collector. Null when install_fargate_metrics = false."
  value       = one(module.fargate_metrics[*].role_arn)
}

output "adot_collector_role_name" {
  description = "Name of the IRSA role for the ADOT Collector. Null when install_fargate_metrics = false."
  value       = one(module.fargate_metrics[*].role_name)
}

output "metrics_log_group" {
  description = "CloudWatch Logs log group for Container Insights EMF performance events. Null when install_fargate_metrics = false."
  value       = one(module.fargate_metrics[*].cloudwatch_log_group)
}

# ── Tracing backend ────────────────────────────────────────────────────────────

output "trace_segment_destination" {
  description = "X-Ray trace segment destination. 'CloudWatchLogs' when Transaction Search is enabled, null otherwise."
  value       = one(module.tracing[*].trace_segment_destination)
}

output "spans_log_group_name" {
  description = "CloudWatch Logs log group where X-Ray spans land. Null when tracing is disabled."
  value       = one(module.tracing[*].spans_log_group_name)
}
