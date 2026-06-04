output "ou_ids" {
  description = "Map of OU path to OU ID."
  value       = { for path, ou in aws_organizations_organizational_unit.ous : path => ou.id }
}
