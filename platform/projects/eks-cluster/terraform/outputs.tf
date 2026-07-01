# ── From eks-cluster ──────────────────────────────────────────────────────────

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Private API server endpoint URL for the EKS cluster."
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = module.cluster.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider associated with the cluster."
  value       = module.cluster.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "Issuer URL of the OIDC provider (without the https:// prefix)."
  value       = module.cluster.oidc_provider_url
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group."
  value       = module.cluster.cluster_security_group_id
}

output "api_ingress_security_group_id" {
  description = "ID of the project-created API server ingress security group. Null when api_server_ingress_cidrs is empty."
  value       = local.create_api_ingress_sg ? aws_security_group.api_ingress[0].id : null
}

# ── From eks-fargate-profiles (null/empty when fargate_profiles is empty) ─────

output "pod_execution_role_names" {
  description = "Map of role key to pod execution IAM role name. Wire the relevant key into eks-ecr-pull. Null when no Fargate profiles are configured."
  value       = one(module.fargate_profiles[*].pod_execution_role_names)
}

output "pod_execution_role_arns" {
  description = "Map of role key to pod execution IAM role ARN. Null when no Fargate profiles are configured."
  value       = one(module.fargate_profiles[*].pod_execution_role_arns)
}

output "pod_execution_role_name" {
  description = "Name of the default pod execution IAM role. Null when no Fargate profiles are configured."
  value       = one(module.fargate_profiles[*].pod_execution_role_name)
}

output "pod_execution_role_arn" {
  description = "ARN of the default pod execution IAM role. Null when no Fargate profiles are configured."
  value       = one(module.fargate_profiles[*].pod_execution_role_arn)
}
