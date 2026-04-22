output "state_machine_arn" {
  description = "ARN of the deploy-trigger Step Functions state machine."
  value       = aws_sfn_state_machine.this.arn
}

output "role_arn" {
  description = "ARN of the Step Functions execution role."
  value       = aws_iam_role.this.arn
}
