output "policy_id" {
  description = "ID of the Organizations backup policy."
  value       = aws_organizations_policy.this.id
}

output "policy_arn" {
  description = "ARN of the Organizations backup policy."
  value       = aws_organizations_policy.this.arn
}

output "policy_content" {
  description = "Rendered policy document (JSON), for review."
  value       = aws_organizations_policy.this.content
}
