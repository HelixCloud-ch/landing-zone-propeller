output "trace_segment_destination" {
  description = "Configured X-Ray trace segment destination. 'CloudWatchLogs' when Transaction Search is enabled, null when disabled."
  value       = one(aws_xray_trace_segment_destination.this[*].destination)
}

output "spans_log_group_name" {
  description = "CloudWatch Logs log group where X-Ray spans are written when Transaction Search is enabled."
  value       = var.enable_transaction_search ? "aws/spans" : null
}

output "indexing_sampling_percentage" {
  description = "Configured trace summary indexing sampling percentage. Null when Transaction Search is disabled."
  value       = one(aws_xray_indexing_rule.default[*].rule[0].probabilistic[0].desired_sampling_percentage)
}
