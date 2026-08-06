output "endpoint" {
  description = "Primary (writer) endpoint for the DocumentDB cluster."
  value       = aws_docdb_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint, automatically load-balanced across replicas."
  value       = aws_docdb_cluster.this.reader_endpoint
}

output "port" {
  description = "Cluster port."
  value       = aws_docdb_cluster.this.port
}

output "cluster_identifier" {
  description = "DocumentDB cluster identifier."
  value       = aws_docdb_cluster.this.cluster_identifier
}

output "arn" {
  description = "ARN of the DocumentDB cluster."
  value       = aws_docdb_cluster.this.arn
}

output "master_username" {
  description = "The master username for the cluster."
  value       = aws_docdb_cluster.this.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master user credentials."
  value       = try(aws_docdb_cluster.this.master_user_secret[0].secret_arn, null)
}

output "security_group_id" {
  description = "ID of the security group used by the cluster (created or caller-provided)."
  value       = local.security_group_id
}

output "cluster_members" {
  description = "List of instance identifiers that are part of the cluster."
  value       = aws_docdb_cluster.this.cluster_members
}
