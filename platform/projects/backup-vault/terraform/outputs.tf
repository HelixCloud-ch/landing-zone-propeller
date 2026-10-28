output "account_id" {
  description = "ID of the account hosting the vault. Wire the central instance's value into source vaults."
  value       = data.aws_caller_identity.current.account_id
}

output "vault_name" {
  description = "Name of the vault."
  value       = module.vault.vault_name
}

output "vault_arn" {
  description = "ARN of the vault. The central instance's value feeds backup-policies.copy_vault_arn."
  value       = module.vault.vault_arn
}

output "kms_key_arn" {
  description = "ARN of the vault key. On a source vault, encrypt backed-up resources with it (e.g. rds-*.kms_key_id)."
  value       = module.vault.kms_key_arn
}

output "role_arn" {
  description = "ARN of the AWS Backup role."
  value       = module.vault.role_arn
}
