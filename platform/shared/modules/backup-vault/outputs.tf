output "vault_name" {
  description = "Name of the backup vault."
  value       = aws_backup_vault.this.name
}

output "vault_arn" {
  description = "ARN of the backup vault."
  value       = aws_backup_vault.this.arn
}

output "kms_key_arn" {
  description = "ARN of the key encrypting the vault (created or supplied)."
  value       = local.kms_key_arn
}

output "kms_key_created" {
  description = "True when the module created the key, false when kms_key_arn was supplied."
  value       = local.create_kms_key
}

output "role_name" {
  description = "Name of the AWS Backup role."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ARN of the AWS Backup role."
  value       = aws_iam_role.this.arn
}
