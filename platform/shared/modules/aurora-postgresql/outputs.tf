output "endpoint" {
  description = "Writer endpoint (hostname) of the Aurora cluster."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint (hostname) of the Aurora cluster."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "Database port."
  value       = aws_rds_cluster.this.port
}

output "db_name" {
  description = "The database name."
  value       = aws_rds_cluster.this.database_name
}

output "username" {
  description = "The master username for the database."
  value       = aws_rds_cluster.this.master_username
}

output "cluster_id" {
  description = "Aurora cluster identifier."
  value       = aws_rds_cluster.this.id
}

output "arn" {
  description = "ARN of the Aurora cluster."
  value       = aws_rds_cluster.this.arn
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master user credentials."
  value       = try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null)
}

output "security_group_id" {
  description = "ID of the security group used by the Aurora cluster (the created one, or the caller-provided security_group_id)."
  value       = local.security_group_id
}
