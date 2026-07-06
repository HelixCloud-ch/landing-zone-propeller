locals {
  subnets_by_tier = jsondecode(var.subnet_ids_json)
  data_subnet_ids = local.subnets_by_tier[var.subnet_tier]
}

module "rds_oracle" {
  source = "../../../shared/modules/rds-oracle"

  identifier = var.identifier
  vpc_id     = var.vpc_id
  subnet_ids = local.data_subnet_ids
  port       = var.port

  # Access
  allowed_cidrs              = var.allowed_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

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

  # Database
  db_name            = var.db_name
  character_set_name = var.character_set_name
  username           = var.username

  # Availability
  multi_az = var.multi_az

  # Backups
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  # Protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot

  # Upgrades
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled

  # S3 Integration
  enable_s3_integration = var.enable_s3_integration

  # JVM
  enable_jvm = var.enable_jvm
}
