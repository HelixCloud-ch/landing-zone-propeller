locals {
  # Secrets Manager manages the master password when a secret KMS key is supplied,
  # otherwise the provided password is used. The two are mutually exclusive
  # (enforced by a validation on the password variable).
  use_managed_password = var.master_user_secret_kms_key_id != null

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
