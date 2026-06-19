output "role_arn" {
  description = "ARN of the IRSA role assumed by the controller's service account. Null when use_pod_identity = true."
  value       = try(aws_iam_role.this[0].arn, null)
}

output "role_name" {
  description = "Name of the IRSA role. Null when use_pod_identity = true."
  value       = try(aws_iam_role.this[0].name, null)
}

output "service_account_name" {
  description = "Name of the Kubernetes service account the controller uses."
  value       = var.service_account_name
}
