# ── DocDB Subnet Group ────────────────────────────────────────────────────────

resource "aws_docdb_subnet_group" "this" {
  name       = var.cluster_identifier
  subnet_ids = var.subnet_ids

  tags = {
    Name = var.cluster_identifier
  }
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "this" {
  count = var.security_group_id == null ? 1 : 0

  name        = "${var.cluster_identifier}-docdb"
  description = "Security group for DocumentDB cluster ${var.cluster_identifier}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.cluster_identifier}-docdb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ingress_cidrs" {
  for_each = toset(var.security_group_id == null ? var.allowed_cidrs : [])

  security_group_id = local.security_group_id
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  description       = "DocumentDB access from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_sgs" {
  for_each = toset(var.security_group_id == null ? var.allowed_security_group_ids : [])

  security_group_id            = local.security_group_id
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
  description                  = "DocumentDB access from ${each.value}"
}

# ── DocumentDB Cluster ────────────────────────────────────────────────────────

resource "aws_docdb_cluster" "this" {
  cluster_identifier = var.cluster_identifier

  # Engine
  engine                      = "docdb"
  engine_version              = var.engine_version
  allow_major_version_upgrade = var.allow_major_version_upgrade

  # Network
  db_subnet_group_name   = aws_docdb_subnet_group.this.name
  vpc_security_group_ids = [local.security_group_id]
  port                   = var.port

  # Storage
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id
  storage_type      = var.storage_type

  # Authentication. Not set when restoring from a snapshot (values come from the snapshot).
  master_username = var.snapshot_identifier != "" ? null : var.master_username

  # Credentials
  manage_master_user_password = local.use_managed_password ? true : null
  master_password_wo          = local.use_managed_password || var.snapshot_identifier != "" ? null : var.master_password
  master_password_wo_version  = local.use_managed_password || var.snapshot_identifier != "" ? null : var.master_password_wo_version

  # Restore
  snapshot_identifier = var.snapshot_identifier != "" ? var.snapshot_identifier : null

  # Backups & Maintenance
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  # Protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : (var.final_snapshot_identifier != "" ? var.final_snapshot_identifier : "${var.cluster_identifier}-final")

  # Upgrades
  apply_immediately = var.apply_immediately

  # Logging
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Parameter group (created only when custom parameters are provided)
  db_cluster_parameter_group_name = length(var.cluster_parameters) > 0 ? aws_docdb_cluster_parameter_group.this[0].name : null
}

# ── Cluster Parameter Group ───────────────────────────────────────────────────
# Created only when cluster_parameters is non-empty.

resource "aws_docdb_cluster_parameter_group" "this" {
  count = length(var.cluster_parameters) > 0 ? 1 : 0

  family = data.aws_docdb_engine_version.this.parameter_group_family
  name   = "${var.cluster_identifier}-${replace(data.aws_docdb_engine_version.this.parameter_group_family, ".", "")}"

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }
}

# ── Cluster Instances ─────────────────────────────────────────────────────────

resource "aws_docdb_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.cluster_identifier}-${count.index}"
  cluster_identifier = aws_docdb_cluster.this.id
  instance_class     = var.instance_class

  enable_performance_insights = var.enable_performance_insights

  apply_immediately = var.apply_immediately
}
