locals {

  use_ephemeral_credential = length(compact([var.credential.secret_name, var.credential.secret_arn, var.credential.parameter_name, var.credential.parameter_arn])) == 1
}

# ── Credential management ─────────────────────────────────────────────────────

module "credential" {
  count  = local.use_ephemeral_credential ? 1 : 0
  source = "../../../shared/modules/ephemeral-credential"

  secret_name    = var.credential.secret_name
  secret_arn     = var.credential.secret_arn
  parameter_name = var.credential.parameter_name
  parameter_arn  = var.credential.parameter_arn

  username         = var.username
  password         = var.credential.password
  password_version = var.credential.password_version
  kms_key_id       = var.credential.kms_key_id
  description      = var.credential.description
  tags             = var.tags
}

# ── RDS Instance ──────────────────────────────────────────────────────────────

module "rds_mariadb" {
  source = "../../../shared/modules/rds-mariadb"

  identifier = var.identifier
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
  port       = var.port

  # Access
  allowed_cidrs              = var.allowed_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

  # Engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id

  # Database
  db_name  = var.db_name
  username = var.username

  # Credentials — ephemeral or Secrets Manager managed
  password                      = local.use_ephemeral_credential ? module.credential[0].password : null
  password_wo_version           = local.use_ephemeral_credential ? module.credential[0].password_version : null
  master_user_secret_kms_key_id = local.use_ephemeral_credential ? null : var.credential.kms_key_id

  # Availability
  multi_az = var.multi_az

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

  # Parameter group
  parameter_group_name = var.parameter_group_name
  parameters           = var.parameters
}
