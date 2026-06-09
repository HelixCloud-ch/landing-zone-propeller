output "ou_ids" {
  description = "Map of OU path to OU ID."
  value = merge(
    { for path, ou in aws_organizations_organizational_unit.level_1 : path => ou.id },
    { for path, ou in aws_organizations_organizational_unit.level_2 : path => ou.id },
    { for path, ou in aws_organizations_organizational_unit.level_3 : path => ou.id },
  )
}

output "ou_names" {
  description = "Map of OU path to OU name."
  value = merge(
    { for path, ou in aws_organizations_organizational_unit.level_1 : path => ou.name },
    { for path, ou in aws_organizations_organizational_unit.level_2 : path => ou.name },
    { for path, ou in aws_organizations_organizational_unit.level_3 : path => ou.name },
  )
}

output "ou_arns" {
  description = "Map of OU path to OU ARN."
  value = merge(
    { for path, ou in aws_organizations_organizational_unit.level_1 : path => ou.arn },
    { for path, ou in aws_organizations_organizational_unit.level_2 : path => ou.arn },
    { for path, ou in aws_organizations_organizational_unit.level_3 : path => ou.arn },
  )
}

output "organization_id" {
  description = "AWS Organization ID."
  value       = data.aws_organizations_organization.current.id
}
