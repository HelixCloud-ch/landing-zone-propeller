output "cluster_api_url" {
  description = "URL of the cluster API server."
  value       = module.rosa_hcp.cluster_api_url
}

output "cluster_id" {
  description = "Unique identifier of the cluster."
  value       = module.rosa_hcp.cluster_id
}

output "cluster_console_url" {
  description = "URL of the cluster web console."
  value       = module.rosa_hcp.cluster_console_url
}

output "cluster_domain" {
  description = "DNS domain of the cluster."
  value       = module.rosa_hcp.cluster_domain
}

output "admin_secret_arn" {
  description = "ARN of the Secrets Manager secret containing cluster admin credentials."
  value       = var.create_admin_user ? aws_secretsmanager_secret.cluster_admin[0].arn : null
}

output "cluster_name" {
  description = "Name of the cluster (pass-through for downstream projects)."
  value       = var.cluster_name
}

output "oidc_endpoint_url" {
  description = "OIDC provider endpoint URL for the cluster (used for IRSA trust policies)."
  value       = module.rosa_hcp.oidc_endpoint_url
}
