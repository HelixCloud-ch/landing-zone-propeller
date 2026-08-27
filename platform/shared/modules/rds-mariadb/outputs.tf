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

output "db_name" {
  description = "The database name."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "The master username for the database."
  value       = aws_db_instance.this.username
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
  description = "ID of the security group used by the RDS instance (created or caller-provided)."
  value       = local.security_group_id
}
output "parameter_group_name" {
  description = "Name of the DB parameter group attached to the instance (existing or module-created), or null when engine default is used."
  value       = local.parameter_group_name
}
