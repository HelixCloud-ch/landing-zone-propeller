output "endpoint" {
  description = "Connection endpoint (address:port)."
  value       = module.rds_postgresql.endpoint
}

output "address" {
  description = "Hostname of the RDS instance."
  value       = module.rds_postgresql.address
}

output "port" {
  description = "Database port."
  value       = module.rds_postgresql.port
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret with master credentials."
  value       = module.rds_postgresql.master_user_secret_arn
}

output "security_group_id" {
  description = "Security group ID for the RDS instance."
  value       = module.rds_postgresql.security_group_id
}

output "db_instance_identifier" {
  description = "RDS instance identifier (used by sleep/wake justfile recipes)."
  value       = var.identifier
}
