locals {
  subnets_by_tier = jsondecode(var.subnet_ids_json)
  data_subnet_ids = local.subnets_by_tier[var.subnet_tier]
}

module "aurora_postgresql" {
  source = "../../../shared/modules/aurora-postgresql"

  identifier = var.identifier
  vpc_id     = var.vpc_id
  subnet_ids = local.data_subnet_ids
  port       = var.port

  # Access
  allowed_cidrs              = var.allowed_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

  # Engine
  engine_version = var.engine_version

  # Scaling
  min_capacity             = var.min_capacity
  max_capacity             = var.max_capacity
  seconds_until_auto_pause = var.seconds_until_auto_pause
  instance_count           = var.instance_count

  # Storage
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # Database
  db_name  = var.db_name
  username = var.username

  # Backups
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # Protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
  snapshot_identifier       = var.snapshot_identifier

  # Upgrades
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled
}
