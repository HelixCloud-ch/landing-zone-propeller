output "lambda_arn" {
  description = "ARN of the propeller autopilot Lambda function."
  value       = aws_lambda_function.autopilot.arn
}
