output "ou_ids" {
  description = "Map of OU path to OU ID."
  value = merge(
    { for path, ou in aws_organizations_organizational_unit.level_1 : path => ou.id },
    { for path, ou in aws_organizations_organizational_unit.level_2 : path => ou.id },
    { for path, ou in aws_organizations_organizational_unit.level_3 : path => ou.id },
  )
}
