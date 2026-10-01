output "key_id" {
  description = "ID of the customer managed key."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "ARN of the customer managed key."
  value       = aws_kms_key.this.arn
}

output "alias_arn" {
  description = "ARN of the key alias."
  value       = aws_kms_alias.this.arn
}
