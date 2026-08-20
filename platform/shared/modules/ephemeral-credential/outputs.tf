locals {
  # Raw value from whichever backend was used
  raw_value = (
    local.create_sm || local.read_sm
    ? ephemeral.aws_secretsmanager_secret_version.this[0].secret_string
    : ephemeral.aws_ssm_parameter.this[0].value
  )
}

output "password" {
  description = "The password value. Ephemeral: never persisted in state or plan."
  value       = local.include_user ? jsondecode(local.raw_value)["password"] : local.raw_value
  ephemeral   = true
  sensitive   = true
}

output "credential_json" {
  description = <<-EOT
    The full stored value as a string. When username is set this is
    JSON {"username":"...","password":"..."}. Ephemeral.
  EOT
  value       = local.raw_value
  ephemeral   = true
  sensitive   = true
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret or SSM parameter."
  value = coalesce(
    local.create_sm ? aws_secretsmanager_secret.this[0].arn : null,
    local.read_sm ? var.secret_arn : null,
    local.create_ssm ? aws_ssm_parameter.this[0].arn : null,
    local.read_ssm ? var.parameter_arn : null,
  )
}

output "password_version" {
  description = "Current password version. Pass to downstream password_wo_version arguments."
  value       = var.password_version
}
