output "role_arn" {
  description = "ARN of the IAM role for the LB Controller. Null when use_pod_identity = true and no existing_role_arn is provided."
  value       = local.effective_role_arn
}

output "role_name" {
  description = "Name of the IAM role for the LB Controller. Null when the role is not managed by this project."
  value       = try(aws_iam_role.this[0].name, null)
}

output "service_account_name" {
  description = "Name of the Kubernetes service account the LB Controller uses."
  value       = var.service_account_name
}
