resource "aws_kms_key" "this" {
  # checkov:skip=CKV_AWS_7: rotation defaults to true; callers disable it only for key material AWS KMS cannot rotate (imported, custom key store).
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_rotation
  rotation_period_in_days = var.enable_rotation ? var.rotation_period_in_days : null
  policy                  = var.policy_json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}
