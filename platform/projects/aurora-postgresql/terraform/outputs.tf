output "endpoint" {
  description = "Writer endpoint (hostname) of the Aurora cluster."
  value       = module.aurora_postgresql.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint (hostname) of the Aurora cluster."
  value       = module.aurora_postgresql.reader_endpoint
}

output "port" {
  description = "Database port."
  value       = module.aurora_postgresql.port
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret with master credentials."
  value       = module.aurora_postgresql.master_user_secret_arn
}

output "security_group_id" {
  description = "Security group ID for the Aurora cluster."
  value       = module.aurora_postgresql.security_group_id
}

output "cluster_identifier" {
  description = "Aurora cluster identifier (used by sleep/wake justfile recipes)."
  value       = var.identifier
}
