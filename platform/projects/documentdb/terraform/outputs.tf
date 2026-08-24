output "endpoint" {
  description = "Primary (writer) endpoint for the DocumentDB cluster."
  value       = module.documentdb.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint, load-balanced across replicas."
  value       = module.documentdb.reader_endpoint
}

output "port" {
  description = "Cluster port."
  value       = module.documentdb.port
}

output "security_group_id" {
  description = "Security group ID for the DocumentDB cluster."
  value       = module.documentdb.security_group_id
}

output "cluster_identifier" {
  description = "DocumentDB cluster identifier (used by sleep/wake justfile recipes)."
  value       = var.cluster_identifier
}

# ── Credential ARNs ───────────────────────────────────────────────────────────

output "master_user_secret_arn" {
  description = "ARN of the DocDB-managed Secrets Manager secret (manage_master_user_password mode only)."
  value       = try(module.documentdb.master_user_secret_arn, null)
}

output "credential_secret_arn" {
  description = "ARN of the Secrets Manager secret created by ephemeral-credential (secret_name mode only)."
  value       = try(module.credential[0].secret_arn, null)
}
