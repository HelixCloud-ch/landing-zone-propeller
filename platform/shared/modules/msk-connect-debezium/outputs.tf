output "connector_arn" {
  description = "ARN of the MSK Connect connector. The project re-exports this as its own Terraform output."
  value       = aws_mskconnect_connector.this.arn
}

output "connector_name" {
  description = "Name of the MSK Connect connector."
  value       = aws_mskconnect_connector.this.name
}

output "service_execution_role_arn" {
  description = "ARN of the connector's service execution role in effect (created or supplied)."
  value       = local.service_execution_role_arn
}

output "required_policy_json" {
  description = "Policy the service execution role needs (apply it to an external role). Null when no grant is needed."
  value       = local.connector_policy_has_statements ? data.aws_iam_policy_document.connector.json : null
}

output "security_group_id" {
  description = "ID of the module-created connector security group; null when not created."
  value       = one(aws_security_group.connector[*].id)
}

output "log_group_name" {
  description = "Name of the module-created CloudWatch log group; null when not created."
  value       = one(aws_cloudwatch_log_group.connector[*].name)
}

output "worker_configuration_arn" {
  description = "ARN of the module-created worker configuration; null when not created."
  value       = one(aws_mskconnect_worker_configuration.this[*].arn)
}

output "connector_configuration" {
  description = "Final merged connector configuration. Sensitive: overrides are unrestricted and may hold plaintext secrets."
  value       = local.connector_configuration
  sensitive   = true
}

output "alarm_arn" {
  description = "ARN of the module-created not-running alarm; null when not created."
  value       = one(aws_cloudwatch_metric_alarm.not_running[*].arn)
}
