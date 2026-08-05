locals {
  # Secrets Manager manages the master password when a secret KMS key is supplied,
  # otherwise the provided password is used. The two are mutually exclusive
  # (enforced by a precondition on the DB instance).
  use_managed_password = var.master_user_secret_kms_key_id != null
}
