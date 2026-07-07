output "role_arn" {
  description = "ARN of the IRSA role assumed by the ADOT Collector service account."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IRSA role assumed by the ADOT Collector service account."
  value       = aws_iam_role.this.name
}

output "collector_namespace" {
  description = "Kubernetes namespace the ADOT Collector is deployed into."
  value       = var.namespace
}

output "cloudwatch_log_group" {
  description = "CloudWatch Logs log group where Container Insights performance EMF events are written."
  value       = "/aws/containerinsights/${var.cluster_name}/performance"
}
