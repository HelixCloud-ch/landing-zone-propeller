output "ram_sharing_enabled" {
  description = "Management account ID if RAM org-sharing is enabled, empty string otherwise."
  value       = var.enable_ram_org_sharing ? one(aws_ram_sharing_with_organization.this[*].id) : ""
}

output "trusted_service_principals" {
  description = "Set of service principals for which trusted access was enabled."
  value       = keys(aws_organizations_aws_service_access.this)
}
