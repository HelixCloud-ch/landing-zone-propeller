output "namespace" {
  description = "Name of the aws-observability namespace created by this module."
  value       = kubernetes_namespace_v1.aws_observability.metadata[0].name
}

output "log_group_name" {
  description = "CloudWatch Logs log group name configured in the Fargate log router."
  value       = var.log_group_name
}
