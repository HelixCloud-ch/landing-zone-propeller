output "pod_execution_role_name" {
  description = "Name of the Fargate pod execution IAM role."
  value       = aws_iam_role.pod_exec.name
}

output "pod_execution_role_arn" {
  description = "ARN of the Fargate pod execution IAM role."
  value       = aws_iam_role.pod_exec.arn
}

output "fargate_profile_names" {
  description = "Names of all Fargate profiles created by this module."
  value       = [for p in aws_eks_fargate_profile.this : p.fargate_profile_name]
}
