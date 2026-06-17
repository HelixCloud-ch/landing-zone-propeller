output "username" {
  description = "IAM user name."
  value       = aws_iam_user.this.name
}

output "user_arn" {
  description = "ARN of the IAM user."
  value       = aws_iam_user.this.arn
}
