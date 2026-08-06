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

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret with master credentials."
  value       = module.documentdb.master_user_secret_arn
}

output "security_group_id" {
  description = "Security group ID for the DocumentDB cluster."
  value       = module.documentdb.security_group_id
}

output "cluster_identifier" {
  description = "DocumentDB cluster identifier (used by sleep/wake justfile recipes)."
  value       = var.cluster_identifier
}
