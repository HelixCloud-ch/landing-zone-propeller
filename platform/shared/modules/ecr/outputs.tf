output "registry_id" {
  description = "The registry ID where templates are configured."
  value       = data.aws_caller_identity.current.account_id
}

output "template_prefixes" {
  description = "List of configured repository creation template prefixes."
  value       = keys(aws_ecr_repository_creation_template.templates)
}
