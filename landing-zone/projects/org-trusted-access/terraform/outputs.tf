output "ram_sharing_enabled" {
  description = "Confirms RAM sharing with AWS Organizations is enabled. Value is the management account ID."
  value       = aws_ram_sharing_with_organization.this.id
}

output "trusted_service_principals" {
  description = "Set of service principals for which trusted access was enabled."
  value       = keys(aws_organizations_aws_service_access.this)
}
