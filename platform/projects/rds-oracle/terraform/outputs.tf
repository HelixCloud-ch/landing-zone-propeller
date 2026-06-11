output "endpoint" {
  description = "Connection endpoint (address:port)."
  value       = module.rds_oracle.endpoint
}

output "address" {
  description = "Hostname of the RDS instance."
  value       = module.rds_oracle.address
}

output "port" {
  description = "Database port."
  value       = module.rds_oracle.port
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret with master credentials."
  value       = module.rds_oracle.master_user_secret_arn
}

output "security_group_id" {
  description = "Security group ID for the RDS instance."
  value       = module.rds_oracle.security_group_id
}
