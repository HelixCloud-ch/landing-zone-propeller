output "endpoint" {
  description = "Connection endpoint in address:port format."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the RDS instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Database port."
  value       = aws_db_instance.this.port
}

output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master user credentials."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "security_group_id" {
  description = "ID of the security group created for the RDS instance."
  value       = aws_security_group.this.id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Oracle data import/export (null if S3 integration disabled)."
  value       = var.enable_s3_integration ? aws_s3_bucket.oracle_data[0].id : null
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Oracle data import/export (null if S3 integration disabled)."
  value       = var.enable_s3_integration ? aws_s3_bucket.oracle_data[0].arn : null
}
