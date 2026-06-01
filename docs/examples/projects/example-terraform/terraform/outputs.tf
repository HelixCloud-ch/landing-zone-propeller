output "echoed_message" {
  description = "The value written to SSM."
  value       = aws_ssm_parameter.echo.value
}
