output "endpoint" {
  description = "Connection endpoint (address:port)."
  value       = module.rds_mariadb.endpoint
}

output "address" {
  description = "Hostname of the RDS instance."
  value       = module.rds_mariadb.address
}

output "port" {
  description = "Database port."
  value       = module.rds_mariadb.port
}

output "security_group_id" {
  description = "Security group ID for the RDS instance."
  value       = module.rds_mariadb.security_group_id
}

output "db_instance_identifier" {
  description = "RDS instance identifier (used by sleep/wake justfile recipes)."
  value       = var.identifier
}

# ── Credential ARNs ───────────────────────────────────────────────────────────

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret (manage_master_user_password mode only)."
  value       = try(module.rds_mariadb.master_user_secret_arn, null)
}

output "credential_secret_arn" {
  description = "ARN of the Secrets Manager secret created by ephemeral-credential (secret_name mode only)."
  value       = try(module.credential[0].secret_arn, null)
}
