locals {
  # Secrets Manager manages the master password when a secret KMS key is supplied,
  # otherwise the provided password is used. The two are mutually exclusive
  # (enforced by a precondition on the DB instance).
  use_managed_password = var.master_user_secret_kms_key_id != null

  # Use the caller-provided security group when set, otherwise the one created here.
  security_group_id = var.security_group_id != null ? var.security_group_id : aws_security_group.this[0].id

  create_parameter_group = length(var.parameters) > 0
  parameter_group_family = "postgres${split(".", var.engine_version)[0]}"
  parameter_group_name   = var.parameter_group_name != null ? var.parameter_group_name : one(aws_db_parameter_group.this[*].name)
}
