output "role_arn" {
  description = "ARN of the IRSA role assumed by the traces collector service account."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IRSA role assumed by the traces collector service account."
  value       = aws_iam_role.this.name
}

output "collector_namespace" {
  description = "Kubernetes namespace the traces collector is deployed into."
  value       = var.namespace
}

output "otlp_grpc_endpoint" {
  description = "In-cluster OTLP gRPC endpoint applications send spans to (OTEL_EXPORTER_OTLP_ENDPOINT)."
  value       = "${local.service_name}.${var.namespace}.svc.cluster.local:4317"
}

output "otlp_http_endpoint" {
  description = "In-cluster OTLP HTTP endpoint applications send spans to. POST OTLP to <endpoint>/v1/traces."
  value       = "${local.service_name}.${var.namespace}.svc.cluster.local:4318"
}
