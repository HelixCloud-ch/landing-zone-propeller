output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Private API server endpoint URL."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster API server TLS certificate."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider. Null when enable_oidc_provider is false."
  value       = var.enable_oidc_provider ? aws_iam_openid_connect_provider.this[0].arn : null
}

output "oidc_provider_url" {
  description = "Issuer URL of the OIDC provider without the https:// prefix. Null when enable_oidc_provider is false."
  value       = var.enable_oidc_provider ? trimprefix(aws_iam_openid_connect_provider.this[0].url, "https://") : null
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
