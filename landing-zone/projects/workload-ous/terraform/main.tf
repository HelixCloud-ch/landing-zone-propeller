data "aws_organizations_organization" "current" {}

locals {
  org_root_id = data.aws_organizations_organization.current.roots[0].id

  # Derive parent from path: "Workloads/Prod" → parent "Workloads".
  # Single-segment paths have no parent (placed under org root).
  ous = { for path, ou in var.ous : path => merge(ou, {
    name   = element(split("/", path), length(split("/", path)) - 1)
    parent = length(split("/", path)) > 1 ? join("/", slice(split("/", path), 0, length(split("/", path)) - 1)) : null
  }) }
}

resource "aws_organizations_organizational_unit" "ous" {
  for_each = local.ous

  name      = each.value.name
  parent_id = each.value.parent != null ? aws_organizations_organizational_unit.ous[each.value.parent].id : local.org_root_id
}

resource "aws_controltower_baseline" "ous" {
  for_each = { for path, ou in local.ous : path => ou if ou.enroll_baseline }

  baseline_identifier = "arn:aws:controltower:::baseline/AWSControlTowerBaseline"
  baseline_version    = each.value.baseline_version
  target_identifier   = aws_organizations_organizational_unit.ous[each.key].arn

  lifecycle {
    ignore_changes = [baseline_version]
  }
}
