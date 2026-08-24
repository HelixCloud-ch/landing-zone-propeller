# Resolve the requested engine version and expose the parameter group family.
# Fails at plan time if the version is not available in the target region.
data "aws_docdb_engine_version" "this" {
  version = var.engine_version
}
