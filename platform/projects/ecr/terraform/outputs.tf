output "registry_id" {
  description = "The ECR registry ID (account ID where ECR is configured)."
  value       = module.ecr.registry_id
}

output "template_prefixes" {
  description = "Configured repository creation template prefixes."
  value       = module.ecr.template_prefixes
}
