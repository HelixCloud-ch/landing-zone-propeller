# ── Ensure DB is started before modifications ─────────────────────────────────
# If the instance was stopped (e.g. by sleep/wake), terraform apply would fail.
# This runs on every apply and starts the instance if it's stopped.

resource "terraform_data" "start_instance" {
  triggers_replace = {
    always_run = plantimestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      DBID="${var.identifier}"
      if ! aws rds describe-db-instances --db-instance-identifier "$DBID" >/dev/null 2>&1; then
        echo "DB $DBID does not exist yet, nothing to start."
        exit 0
      fi
      STATUS=$(aws rds describe-db-instances --db-instance-identifier "$DBID" \
        --query "DBInstances[0].DBInstanceStatus" --output text)
      echo "DB $DBID status: $STATUS"
      if [ "$STATUS" = "stopped" ]; then
        echo "Starting DB $DBID..."
        aws rds start-db-instance --db-instance-identifier "$DBID"
        aws rds wait db-instance-available --db-instance-identifier "$DBID"
      fi
    EOT
  }
}

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
  description = "Security group for RDS PostgreSQL instance ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.identifier}-rds"
  }
}

resource "aws_vpc_security_group_egress_rule" "this" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_cidrs" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  description       = "PostgreSQL access from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_sgs" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
  description                  = "PostgreSQL access from ${each.value}"
}

# ── RDS PostgreSQL Instance ───────────────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier = var.identifier

  depends_on = [terraform_data.start_instance]

  # Engine. instance_class is taken from the orderable data source so an invalid
  # class/version/storage override fails at plan time. engine_version stays the
  # major version so AWS manages the minor without drift.
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
  vpc_security_group_ids = [aws_security_group.this.id]
  multi_az               = var.multi_az
  port                   = var.port
  publicly_accessible    = false

  # Database. Not set when restoring from a snapshot (values come from the snapshot).
  db_name  = var.snapshot_identifier != "" ? null : var.db_name
  username = var.snapshot_identifier != "" ? null : var.username

  # Credentials: Secrets Manager when a secret KMS key is supplied, otherwise the
  # provided password via the write-only password_wo argument (kept out of state
  # and plan). Neither is set on snapshot restore (credentials come from the snapshot).
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

  # Parameter group
  parameter_group_name = var.parameter_group_name

  lifecycle {
    ignore_changes = [
      # Storage autoscaling adjusts this dynamically
      allocated_storage,
    ]
    precondition {
      condition     = !(var.password != null && var.master_user_secret_kms_key_id != null)
      error_message = "Pass either 'password' or 'master_user_secret_kms_key_id', not both."
    }
    precondition {
      condition     = var.snapshot_identifier != "" || var.password != null || var.master_user_secret_kms_key_id != null
      error_message = "Provide credentials: set 'master_user_secret_kms_key_id' for Secrets Manager mode, or 'password' for password mode (unless restoring from a snapshot)."
    }
  }
}
