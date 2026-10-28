output "policy_ids" {
  description = "Map of policy name to Organizations backup policy ID."
  value       = { for k, m in module.backup_policy : k => m.policy_id }
}

output "policy_arns" {
  description = "Map of policy name to Organizations backup policy ARN."
  value       = { for k, m in module.backup_policy : k => m.policy_arn }
}

output "target_ids" {
  description = "Map of policy name to the root, OU or account IDs it is attached to."
  value       = { for k, p in local.policies : k => p.target_ids }
}
