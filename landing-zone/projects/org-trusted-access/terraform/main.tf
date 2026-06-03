resource "aws_ram_sharing_with_organization" "this" {
  count = var.enable_ram_org_sharing ? 1 : 0
}

resource "aws_organizations_aws_service_access" "this" {
  for_each = toset(var.trusted_service_principals)

  service_principal = each.value
}
