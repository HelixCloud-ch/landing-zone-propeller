data "aws_organizations_organization" "this" {}

locals {
  create_log_archive_account = var.log_archive_account_email != ""
  create_audit_account       = var.audit_account_email != ""
  create_backup_accounts     = var.backup_admin_account_email != "" && var.backup_central_account_email != ""
}

# ── Security OU ──────────────────────────────────────────────────────────────

resource "aws_organizations_organizational_unit" "security" {
  name      = var.security_ou_name
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

# ── Service integration accounts ─────────────────────────────────────────────

resource "aws_organizations_account" "log_archive" {
  count = local.create_log_archive_account ? 1 : 0

  name      = var.log_archive_account_name
  email     = var.log_archive_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name]
  }
}

resource "aws_organizations_account" "audit" {
  count = local.create_audit_account ? 1 : 0

  name      = var.audit_account_name
  email     = var.audit_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name]
  }
}

# ── Backup accounts (optional) ───────────────────────────────────────────────

resource "aws_organizations_account" "backup_admin" {
  count = local.create_backup_accounts ? 1 : 0

  name      = var.backup_admin_account_name
  email     = var.backup_admin_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name]
  }
}

resource "aws_organizations_account" "backup_central" {
  count = local.create_backup_accounts ? 1 : 0

  name      = var.backup_central_account_name
  email     = var.backup_central_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name]
  }
}

# ── AWSControlTowerAdmin ─────────────────────────────────────────────────────

resource "aws_iam_role" "control_tower_admin" {
  count = var.create_iam_roles ? 1 : 0

  name = "AWSControlTowerAdmin"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "controltower.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "control_tower_admin" {
  count = var.create_iam_roles ? 1 : 0

  name = "AWSControlTowerAdminPolicy"
  role = aws_iam_role.control_tower_admin[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ec2:DescribeAvailabilityZones"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "control_tower_admin" {
  count = var.create_iam_roles ? 1 : 0

  role       = aws_iam_role.control_tower_admin[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSControlTowerServiceRolePolicy"
}

# ── AWSControlTowerCloudTrailRole ────────────────────────────────────────────

resource "aws_iam_role" "control_tower_cloudtrail" {
  count = var.create_iam_roles ? 1 : 0

  name = "AWSControlTowerCloudTrailRole"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "control_tower_cloudtrail" {
  count = var.create_iam_roles ? 1 : 0

  role       = aws_iam_role.control_tower_cloudtrail[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSControlTowerCloudTrailRolePolicy"
}

# ── AWSControlTowerStackSetRole ──────────────────────────────────────────────

resource "aws_iam_role" "control_tower_stackset" {
  count = var.create_iam_roles ? 1 : 0

  name = "AWSControlTowerStackSetRole"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudformation.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "control_tower_stackset" {
  count = var.create_iam_roles ? 1 : 0

  name = "AWSControlTowerStackSetRolePolicy"
  role = aws_iam_role.control_tower_stackset[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::*:role/AWSControlTowerExecution"
    }]
  })
}

# ── AWSControlTowerConfigAggregatorRoleForOrganizations ──────────────────────

resource "aws_iam_role" "control_tower_config_aggregator" {
  count = var.create_iam_roles ? 1 : 0

  name = "AWSControlTowerConfigAggregatorRoleForOrganizations"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "control_tower_config_aggregator" {
  count = var.create_iam_roles ? 1 : 0

  role       = aws_iam_role.control_tower_config_aggregator[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}
