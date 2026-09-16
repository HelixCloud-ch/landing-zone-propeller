locals {
  # Option groups require only the major engine version (e.g. "19"), but
  # callers may pass a full version string like "19.0.0.0.0".
  major_engine_version = split(".", var.engine_version)[0]

  # RDS manages the master password (via Secrets Manager) unless the caller
  # explicitly opts out or is restoring from a snapshot. Cannot derive this
  # from var.password because password is ephemeral and ephemeral values may
  # not flow into state-persisting attributes.
  use_managed_password = var.manage_master_user_password && var.snapshot_identifier == ""

  # Use the caller-provided security group when set, otherwise the one created here.
  security_group_id = var.security_group_id != null ? var.security_group_id : aws_security_group.this[0].id

  s3_option = var.enable_s3_integration ? [{
    option_name = "S3_INTEGRATION"
    version     = "1.0"
    port        = null
    settings    = []
  }] : []

  jvm_option = var.enable_jvm ? [{
    option_name = "JVM"
    version     = null
    port        = null
    settings    = []
  }] : []

  all_options = concat(local.s3_option, local.jvm_option, var.additional_options)
}
