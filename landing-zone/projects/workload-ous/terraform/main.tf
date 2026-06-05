locals {

  # Enrich each entry with computed name, parent path, and depth
  all_ous = { for path, ou in var.ous : path => merge(ou, {
    name   = element(split("/", path), length(split("/", path)) - 1)
    parent = length(split("/", path)) > 1 ? join("/", slice(split("/", path), 0, length(split("/", path)) - 1)) : null
    depth  = length(split("/", path))
  }) }

  # Split by level
  level_1 = { for path, ou in local.all_ous : path => ou if ou.depth == 1 }
  level_2 = { for path, ou in local.all_ous : path => ou if ou.depth == 2 }
  level_3 = { for path, ou in local.all_ous : path => ou if ou.depth == 3 }
}

# ── Validation ────────────────────────────────────────────────────────────────

resource "terraform_data" "validate_max_depth" {
  lifecycle {
    precondition {
      condition     = max([for v in local.all_ous : v.depth]...) <= 3
      error_message = "Maximum OU nesting depth is 3 (e.g. 'A/B/C'). Deeper paths are not supported."
    }
  }
}

# ── Level 1: direct children of org root ─────────────────────────────────────

resource "aws_organizations_organizational_unit" "level_1" {
  for_each = local.level_1

  name      = each.value.name
  parent_id = local.org_root_id

  depends_on = [terraform_data.validate_max_depth]
}

# ── Level 2: children of level 1 OUs ─────────────────────────────────────────

resource "aws_organizations_organizational_unit" "level_2" {
  for_each = local.level_2

  name      = each.value.name
  parent_id = aws_organizations_organizational_unit.level_1[each.value.parent].id
}

# ── Level 3: children of level 2 OUs ─────────────────────────────────────────

resource "aws_organizations_organizational_unit" "level_3" {
  for_each = local.level_3

  name      = each.value.name
  parent_id = aws_organizations_organizational_unit.level_2[each.value.parent].id
}

# ── Control Tower baseline enrollment ─────────────────────────────────────────

locals {
  # Merge all OUs with their resource references for baseline enrollment
  all_ou_arns = merge(
    { for k, v in aws_organizations_organizational_unit.level_1 : k => v.arn },
    { for k, v in aws_organizations_organizational_unit.level_2 : k => v.arn },
    { for k, v in aws_organizations_organizational_unit.level_3 : k => v.arn },
  )

  baseline_ous = { for path, ou in local.all_ous : path => ou if ou.enroll_baseline }
}

resource "aws_controltower_baseline" "ous" {
  for_each = local.baseline_ous

  baseline_identifier = local.baseline_arn
  baseline_version    = each.value.baseline_version
  target_identifier   = local.all_ou_arns[each.key]

  lifecycle {
    ignore_changes = [baseline_version]
  }
}
