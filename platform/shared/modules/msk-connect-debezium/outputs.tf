output "connector_arn" {
  description = "ARN of the MSK Connect connector. The project re-exports this as its own Terraform output."
  value       = aws_mskconnect_connector.this.arn
}

output "connector_name" {
  description = "Name of the MSK Connect connector."
  value       = aws_mskconnect_connector.this.name
}

output "service_execution_role_arn" {
  description = "ARN of the connector's service execution role."
  value       = aws_iam_role.connector.arn
}

output "security_group_id" {
  description = "ID of the security group attached to the connector's ENIs."
  value       = aws_security_group.connector.id
}

output "log_group_name" {
  description = "Name of the CloudWatch log group receiving connector logs."
  value       = aws_cloudwatch_log_group.connector.name
}

output "worker_configuration_arn" {
  description = "ARN of the connector's worker configuration."
  value       = aws_mskconnect_worker_configuration.this.arn
}

output "alarm_arn" {
  description = "ARN of the connector not-running CloudWatch alarm."
  value       = aws_cloudwatch_metric_alarm.not_running.arn
}
