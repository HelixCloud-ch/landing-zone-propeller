output "pod_execution_role_arns" {
  description = "Map of role key to effective IAM role ARN (module-created or externally supplied), including 'default'."
  value       = local.role_arns
}

output "pod_execution_role_names" {
  description = "Map of role key to IAM role name, for module-managed roles only. External roles are excluded — their names are owned elsewhere."
  value       = { for k in local.managed_role_keys : k => aws_iam_role.pod_exec[k].name }
}

output "pod_execution_role_arn" {
  description = "Effective ARN of the default Fargate pod execution role. Convenience accessor for pod_execution_role_arns[\"default\"]."
  value       = local.role_arns["default"]
}

output "pod_execution_role_name" {
  description = "Name of the default Fargate pod execution role when this module manages it; null when the default role is externally supplied."
  value       = contains(local.managed_role_keys, "default") ? aws_iam_role.pod_exec["default"].name : null
}

output "fargate_profile_names" {
  description = "Names of all Fargate profiles created by this module."
  value       = [for p in aws_eks_fargate_profile.this : p.fargate_profile_name]
}
