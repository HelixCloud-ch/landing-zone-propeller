output "primary_endpoint" {
  description = "Primary endpoint address (for writes)."
  value       = module.redis.primary_endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint address (load-balanced across replicas)."
  value       = module.redis.reader_endpoint
}

output "port" {
  description = "Redis port."
  value       = module.redis.port
}

output "security_group_id" {
  description = "Security group ID for the ElastiCache cluster."
  value       = module.redis.security_group_id
}

output "connection_url" {
  description = "Connection URL for Redis clients (rediss:// when TLS enabled, redis:// otherwise)."
  value       = "${var.transit_encryption_enabled ? "rediss" : "redis"}://${module.redis.primary_endpoint}:${module.redis.port}"
}
