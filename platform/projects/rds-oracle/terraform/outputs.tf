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

output "security_group_id" {
  description = "Security group ID for the RDS instance."
  value       = module.rds_oracle.security_group_id
}

output "s3_bucket_name" {
  description = "S3 bucket for Oracle Data Pump import/export (null if S3 integration disabled)."
  value       = module.rds_oracle.s3_bucket_name
}

output "db_instance_identifier" {
  description = "RDS instance identifier."
  value       = var.identifier
}

# ── Credential ARNs ───────────────────────────────────────────────────────────

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret (manage_master_user_password mode only)."
  value       = try(module.rds_oracle.master_user_secret_arn, null)
}

output "credential_secret_arn" {
  description = "ARN of the Secrets Manager secret created by ephemeral-credential (secret_name mode only)."
  value       = try(module.credential[0].secret_arn, null)
}
