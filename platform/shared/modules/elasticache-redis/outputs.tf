output "primary_endpoint" {
  description = "Primary endpoint address (for writes)."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint address (load-balanced across replicas)."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Redis port."
  value       = var.port
}

output "security_group_id" {
  description = "Security group ID for the ElastiCache cluster."
  value       = aws_security_group.this.id
}
