locals {
  subnets_by_tier = jsondecode(var.subnet_ids_json)
  data_subnet_ids = local.subnets_by_tier[var.subnet_tier]
}

module "redis" {
  source = "../../../shared/modules/elasticache-redis"

  identifier = var.identifier
  vpc_id     = var.vpc_id
  subnet_ids = local.data_subnet_ids
  port       = var.port

  # Access
  allowed_cidrs              = var.allowed_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

  # Engine
  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_replicas         = var.num_replicas
  parameter_group_name = var.parameter_group_name

  # Encryption
  transit_encryption_enabled = var.transit_encryption_enabled
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  kms_key_id                 = var.kms_key_id

  # Availability
  multi_az_enabled           = var.multi_az_enabled
  automatic_failover_enabled = var.automatic_failover_enabled

  # Maintenance & snapshots
  maintenance_window       = var.maintenance_window
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window

  # Upgrades
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
}
