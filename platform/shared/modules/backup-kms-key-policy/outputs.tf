output "json" {
  description = "Key policy document (JSON), for kms-key's policy_json."
  value       = data.aws_iam_policy_document.this.json
}
