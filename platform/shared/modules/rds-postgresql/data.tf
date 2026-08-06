# Resolve the requested major version to a concrete, available version and expose
# its parameter group family. Fails at plan time on an unknown version.
data "aws_rds_engine_version" "this" {
  engine  = var.engine
  version = var.engine_version
  latest  = true
}

# Validate that version + instance class + storage type is an orderable combination
# in this region. Fails at plan time on an invalid instance_class / version override.
data "aws_rds_orderable_db_instance" "this" {
  engine                      = var.engine
  engine_version              = data.aws_rds_engine_version.this.version_actual
  instance_class              = var.instance_class
  storage_type                = var.storage_type
  supports_storage_encryption = var.storage_encrypted ? true : null
}
