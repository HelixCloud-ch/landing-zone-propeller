locals {
  # Derive mode and backend from which variable is set
  create_sm  = var.secret_name != null
  read_sm    = var.secret_arn != null
  create_ssm = var.parameter_name != null
  read_ssm   = var.parameter_arn != null

  is_create    = local.create_sm || local.create_ssm
  include_user = var.username != null

  # Build the credential value to store
  secret_value = (
    local.include_user
    ? jsonencode({
      username = "${var.username.prefix}${ephemeral.aws_secretsmanager_random_password.username[0].random_password}"
      password = ephemeral.aws_secretsmanager_random_password.password[0].random_password
    })
    : ephemeral.aws_secretsmanager_random_password.password[0].random_password
  )
}

# ══════════════════════════════════════════════════════════════════════════════
# Password generation (create modes)
# ══════════════════════════════════════════════════════════════════════════════

ephemeral "aws_secretsmanager_random_password" "password" {
  count = local.is_create ? 1 : 0

  password_length            = var.password.length
  exclude_characters         = var.password.exclude_characters
  exclude_lowercase          = var.password.exclude_lowercase
  exclude_numbers            = var.password.exclude_numbers
  exclude_punctuation        = var.password.exclude_punctuation
  exclude_uppercase          = var.password.exclude_uppercase
  include_space              = var.password.include_space
  require_each_included_type = var.password.require_each_included_type
}

# ══════════════════════════════════════════════════════════════════════════════
# Username generation (create modes, when username is configured)
# ══════════════════════════════════════════════════════════════════════════════
# Generates a random suffix. The full username is "{prefix}{suffix}" — the
# caller controls the separator (or lack thereof) via the prefix value.

ephemeral "aws_secretsmanager_random_password" "username" {
  count = local.is_create && local.include_user ? 1 : 0

  password_length            = var.username.length
  exclude_characters         = var.username.exclude_characters
  exclude_lowercase          = var.username.exclude_lowercase
  exclude_numbers            = var.username.exclude_numbers
  exclude_uppercase          = var.username.exclude_uppercase
  exclude_punctuation        = var.username.exclude_punctuation
  include_space              = var.username.include_space
  require_each_included_type = false
}

# ══════════════════════════════════════════════════════════════════════════════
# Secrets Manager — create (secret_name)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_secretsmanager_secret" "this" {
  #checkov:skip=CKV2_AWS_57:Rotation is explicit via password_version bump, no Lambda needed
  count = local.create_sm ? 1 : 0

  name        = var.secret_name
  description = var.description
  kms_key_id  = var.kms_key_id

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  count = local.create_sm ? 1 : 0

  secret_id                = aws_secretsmanager_secret.this[0].id
  secret_string_wo         = local.secret_value
  secret_string_wo_version = var.password_version
}

# ══════════════════════════════════════════════════════════════════════════════
# Secrets Manager — read (secret_arn or after create)
# ══════════════════════════════════════════════════════════════════════════════

ephemeral "aws_secretsmanager_secret_version" "this" {
  count = local.create_sm || local.read_sm ? 1 : 0

  secret_id = local.create_sm ? aws_secretsmanager_secret.this[0].id : var.secret_arn

  depends_on = [aws_secretsmanager_secret_version.this]
}

# ══════════════════════════════════════════════════════════════════════════════
# SSM Parameter Store — create (parameter_name)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_ssm_parameter" "this" {
  count = local.create_ssm ? 1 : 0

  name             = var.parameter_name
  description      = var.description
  type             = "SecureString"
  key_id           = var.kms_key_id
  value_wo         = local.secret_value
  value_wo_version = var.password_version

  tags = var.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# SSM Parameter Store — read (parameter_arn or after create)
# ══════════════════════════════════════════════════════════════════════════════

ephemeral "aws_ssm_parameter" "this" {
  count = local.create_ssm || local.read_ssm ? 1 : 0

  arn = local.create_ssm ? aws_ssm_parameter.this[0].arn : var.parameter_arn

  depends_on = [aws_ssm_parameter.this]
}
