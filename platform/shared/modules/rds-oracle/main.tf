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
  name        = "${var.identifier}-rds"
  description = "Security group for RDS Oracle instance ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.identifier}-rds"
  }
}

resource "aws_security_group_rule" "ingress_cidrs" {
  count = length(var.allowed_cidrs) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidrs
  security_group_id = aws_security_group.this.id
  description       = "Oracle access from allowed CIDRs"
}

resource "aws_security_group_rule" "ingress_sgs" {
  for_each = toset(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.this.id
  description              = "Oracle access from ${each.value}"
}

# ── RDS Oracle Instance ───────────────────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier = var.identifier

  # Engine
  engine         = var.engine
  engine_version = var.engine_version
  license_model  = var.license_model
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  multi_az               = var.multi_az
  port                   = var.port
  publicly_accessible    = false

  # Database
  db_name            = var.db_name
  character_set_name = var.character_set_name
  username           = var.username

  # Credentials managed by Secrets Manager
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_id

  # Maintenance & backups
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  # Protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  # Upgrades
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = false
  apply_immediately           = var.apply_immediately

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled

  # Parameter & option groups
  parameter_group_name = var.parameter_group_name
  option_group_name    = var.option_group_name != null ? var.option_group_name : local.create_option_group ? aws_db_option_group.this[0].name : null

  lifecycle {
    ignore_changes = [
      # Storage autoscaling adjusts this dynamically
      allocated_storage,
    ]
  }
}
