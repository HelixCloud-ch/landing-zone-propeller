# ── Subnet Group ──────────────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "this" {
  name       = var.identifier
  subnet_ids = var.subnet_ids

  tags = {
    Name = var.identifier
  }
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "this" {
  name        = "${var.identifier}-redis"
  description = "Security group for ElastiCache ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.identifier}-redis"
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
  description       = "Redis access from allowed CIDRs"
}

resource "aws_security_group_rule" "ingress_sgs" {
  for_each = toset(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.this.id
  description              = "Redis access from ${each.value}"
}

# ── ElastiCache Replication Group ─────────────────────────────────────────────

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.identifier
  description          = "ElastiCache ${var.engine} - ${var.identifier}"

  # Engine
  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = var.parameter_group_name

  # Topology: single shard with replicas
  num_cache_clusters         = var.num_replicas + 1
  automatic_failover_enabled = var.num_replicas >= 1 ? var.automatic_failover_enabled : false
  multi_az_enabled           = var.num_replicas >= 1 ? var.multi_az_enabled : false

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  # Encryption
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  kms_key_id                 = var.kms_key_id
  transit_encryption_enabled = var.transit_encryption_enabled

  # Maintenance & snapshots
  maintenance_window       = var.maintenance_window
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window

  # Upgrades
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
}
