locals {
  subnets_by_tier = jsondecode(var.subnet_ids_json)
  data_subnet_ids = local.subnets_by_tier[var.subnet_tier]

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

  username         = var.master_username
  password         = var.credential.password
  password_version = var.credential.password_version
  kms_key_id       = var.credential.kms_key_id
  description      = var.credential.description
  tags             = var.tags
}

# ── DocumentDB Cluster ────────────────────────────────────────────────────────

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
  master_username = var.master_username

  # Credentials — ephemeral or Secrets Manager managed
  master_password               = local.use_ephemeral_credential ? module.credential[0].password : null
  master_password_wo_version    = local.use_ephemeral_credential ? module.credential[0].password_version : null
  master_user_secret_kms_key_id = local.use_ephemeral_credential ? null : var.credential.kms_key_id

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
