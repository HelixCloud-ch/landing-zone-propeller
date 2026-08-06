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

  name        = "${var.identifier}-aurora"
  description = "Security group for Aurora PostgreSQL cluster ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.identifier}-aurora"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ingress_cidrs" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = local.security_group_id
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  description       = "PostgreSQL access from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_sgs" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = local.security_group_id
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
  description                  = "PostgreSQL access from ${each.value}"
}

# ── Aurora PostgreSQL Cluster ─────────────────────────────────────────────────

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.identifier

  # Engine. engine_version stays the major version so AWS manages the minor
  # without drift. engine_mode "provisioned" + serverlessv2_scaling_configuration
  # selects Serverless v2 capacity (min_capacity = 0 enables scale-to-zero).
  engine         = local.engine
  engine_version = var.engine_version
  engine_mode    = "provisioned"

  serverlessv2_scaling_configuration {
    min_capacity             = var.min_capacity
    max_capacity             = var.max_capacity
    seconds_until_auto_pause = var.min_capacity == 0 ? var.seconds_until_auto_pause : null
  }

  # Storage
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [local.security_group_id]
  port                   = var.port

  # Database. Not set when restoring from a snapshot (values come from the snapshot).
  database_name   = var.snapshot_identifier != "" ? null : var.db_name
  master_username = var.snapshot_identifier != "" ? null : var.username

  # Credentials: Secrets Manager when a secret KMS key is supplied, otherwise the
  # provided password via the write-only master_password_wo argument (kept out of
  # state and plan). Neither is set on snapshot restore (credentials come from the
  # snapshot).
  manage_master_user_password   = local.use_managed_password ? true : null
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_id
  master_password_wo            = local.use_managed_password || var.snapshot_identifier != "" ? null : var.password
  master_password_wo_version    = local.use_managed_password || var.snapshot_identifier != "" ? null : var.password_wo_version

  # Restore
  snapshot_identifier = var.snapshot_identifier != "" ? var.snapshot_identifier : null

  # Maintenance & backups
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true

  # Protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : (var.final_snapshot_identifier != "" ? var.final_snapshot_identifier : "${var.identifier}-final")

  # Upgrades
  allow_major_version_upgrade = false
  apply_immediately           = var.apply_immediately

  # Parameter group
  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name

  lifecycle {
    precondition {
      condition     = !(var.min_capacity == 0 && var.performance_insights_enabled)
      error_message = "Performance Insights forces a non-zero minimum ACU; disable it to keep scale-to-zero auto-pause (min_capacity = 0)."
    }
  }
}

# ── Aurora Serverless v2 Instances ────────────────────────────────────────────

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.identifier}-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_parameter_group_name    = var.db_parameter_group_name
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  publicly_accessible        = false

  performance_insights_enabled = var.performance_insights_enabled
}
