output "connector_arn" {
  description = "ARN of the MSK Connect Debezium connector."
  value       = module.debezium.connector_arn
}

output "connector_name" {
  description = "Name of the MSK Connect connector."
  value       = module.debezium.connector_name
}

output "service_execution_role_arn" {
  description = "ARN of the connector's service execution role in effect (created or supplied)."
  value       = module.debezium.service_execution_role_arn
}

output "required_policy_json" {
  description = "Policy the service execution role needs; apply it to an external role. Null when no grant is needed."
  value       = module.debezium.required_policy_json
}

output "security_group_id" {
  description = "ID of the module-created connector security group; null when not created."
  value       = module.debezium.security_group_id
}

output "server_id" {
  description = "Debezium database.server.id in effect (supplied or derived from identifier)."
  value       = local.server_id
}
