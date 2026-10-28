output "key_arns" {
  description = "Map of key name to key ARN."
  value       = { for name, k in module.keys : name => k.key_arn }
}

output "key_ids" {
  description = "Map of key name to key ID."
  value       = { for name, k in module.keys : name => k.key_id }
}

output "alias_arns" {
  description = "Map of key name to alias ARN."
  value       = { for name, k in module.keys : name => k.alias_arn }
}
