output "parameter_name" {
  value       = aws_ssm_parameter.test.name
  description = "Name of the created SSM parameter."
}

output "parameter_arn" {
  value       = aws_ssm_parameter.test.arn
  description = "ARN of the created SSM parameter."
}
