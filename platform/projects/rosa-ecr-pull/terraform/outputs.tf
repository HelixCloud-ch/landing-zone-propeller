output "worker_role_name" {
  description = "Worker IAM role that received ECR pull permissions."
  value       = data.aws_iam_role.worker.name
}

output "policy_name" {
  description = "Name of the inline policy attached."
  value       = aws_iam_role_policy.ecr_pull.name
}
