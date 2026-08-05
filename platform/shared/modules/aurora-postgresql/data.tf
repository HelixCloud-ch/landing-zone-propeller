# Resolve the requested major version to a concrete, available version and expose
# its parameter group family. Fails at plan time on an unknown version.
data "aws_rds_engine_version" "this" {
  engine  = local.engine
  version = var.engine_version
  latest  = true
}

# Validate that the Serverless v2 instance class is orderable for this engine
# version in the region. Fails at plan time on an unsupported version.
data "aws_rds_orderable_db_instance" "this" {
  engine         = local.engine
  engine_version = data.aws_rds_engine_version.this.version_actual
  instance_class = "db.serverless"
}
