locals {
  subnets_by_tier = jsondecode(var.subnet_ids_json)
  data_subnet_ids = local.subnets_by_tier[var.subnet_tier]
}

module "documentdb" {
  source = "../../../shared/modules/documentdb"

  cluster_identifier = var.cluster_identifier
  vpc_id             = var.vpc_id
  subnet_ids         = local.data_subnet_ids
  port               = var.port

  # Access
  allowed_cidrs              = var.allowed_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

  # Engine
  engine_version = var.engine_version

  # Instances
  instance_count = var.instance_count
  instance_class = var.instance_class

  # Storage
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id
  storage_type      = var.storage_type

  # Authentication
  master_username            = var.master_username
  master_password            = var.master_password
  master_password_wo_version = var.master_password_wo_version

  # Backups
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  # Protection
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
  snapshot_identifier       = var.snapshot_identifier

  # Upgrades
  apply_immediately           = var.apply_immediately
  allow_major_version_upgrade = var.allow_major_version_upgrade

  # Parameters
  cluster_parameters = var.cluster_parameters

  # Monitoring
  enable_performance_insights = var.enable_performance_insights

  # Logging
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
}
