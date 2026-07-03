output "project_name" {
  description = "Name of the VPC-attached CodeBuild project. Use as `runner` value in pipeline steps."
  value       = aws_codebuild_project.runner.name
}

output "project_arn" {
  description = "ARN of the CodeBuild project."
  value       = aws_codebuild_project.runner.arn
}

output "service_role_arn" {
  description = "ARN of the CodeBuild service role."
  value       = aws_iam_role.codebuild.arn
}

output "security_group_id" {
  description = "Security group ID attached to the CodeBuild ENI."
  value       = aws_security_group.codebuild.id
}
