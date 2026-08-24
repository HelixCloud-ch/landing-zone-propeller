# ── DB Subnet Group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name       = var.identifier
  subnet_ids = var.subnet_ids

  tags = {
    Name = var.identifier
  }
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "this" {
  count = var.security_group_id == null ? 1 : 0

  name        = "${var.identifier}-rds"
  description = "Security group for RDS PostgreSQL instance ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.identifier}-rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ingress_cidrs" {
  for_each = toset(var.security_group_id == null ? var.allowed_cidrs : [])

  security_group_id = local.security_group_id
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  description       = "PostgreSQL access from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_sgs" {
  for_each = toset(var.security_group_id == null ? var.allowed_security_group_ids : [])

  security_group_id            = local.security_group_id
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
  description                  = "PostgreSQL access from ${each.value}"
}

# ── RDS PostgreSQL Instance ───────────────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier = var.identifier

  # Engine
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = data.aws_rds_orderable_db_instance.this.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [local.security_group_id]
  multi_az               = var.multi_az
  port                   = var.port
  publicly_accessible    = false

  # Database. Not set when restoring from a snapshot (values come from the snapshot).
  db_name  = var.snapshot_identifier != "" ? null : var.db_name
  username = var.snapshot_identifier != "" ? null : var.username

  # Credentials
  manage_master_user_password   = local.use_managed_password ? true : null
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_id
  password_wo                   = local.use_managed_password || var.snapshot_identifier != "" ? null : var.password
  password_wo_version           = local.use_managed_password || var.snapshot_identifier != "" ? null : var.password_wo_version

  # Restore
  snapshot_identifier = var.snapshot_identifier != "" ? var.snapshot_identifier : null

  # Maintenance & backups
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  # Protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : (var.final_snapshot_identifier != "" ? var.final_snapshot_identifier : "${var.identifier}-final")

  # Upgrades
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = false
  apply_immediately           = var.apply_immediately

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled

  # Logging
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Parameter group
  parameter_group_name = var.parameter_group_name

  lifecycle {
    ignore_changes = [
      allocated_storage,
    ]
  }
}
