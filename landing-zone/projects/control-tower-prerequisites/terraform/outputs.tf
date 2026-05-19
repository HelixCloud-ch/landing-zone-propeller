output "security_ou_id" {
  description = "ID of the Security OU."
  value       = aws_organizations_organizational_unit.security.id
}

output "log_archive_account_id" {
  description = "AWS account ID of the Log Archive account (empty if not created)."
  value       = length(aws_organizations_account.log_archive) > 0 ? aws_organizations_account.log_archive[0].id : ""
}

output "audit_account_id" {
  description = "AWS account ID of the Security Tooling (Audit) account (empty if not created)."
  value       = length(aws_organizations_account.audit) > 0 ? aws_organizations_account.audit[0].id : ""
}

output "control_tower_admin_role_arn" {
  description = "ARN of the AWSControlTowerAdmin IAM role (empty if not created)."
  value       = length(aws_iam_role.control_tower_admin) > 0 ? aws_iam_role.control_tower_admin[0].arn : ""
}

output "control_tower_cloudtrail_role_arn" {
  description = "ARN of the AWSControlTowerCloudTrailRole IAM role (empty if not created)."
  value       = length(aws_iam_role.control_tower_cloudtrail) > 0 ? aws_iam_role.control_tower_cloudtrail[0].arn : ""
}

output "control_tower_stackset_role_arn" {
  description = "ARN of the AWSControlTowerStackSetRole IAM role (empty if not created)."
  value       = length(aws_iam_role.control_tower_stackset) > 0 ? aws_iam_role.control_tower_stackset[0].arn : ""
}

output "control_tower_config_aggregator_role_arn" {
  description = "ARN of the AWSControlTowerConfigAggregatorRoleForOrganizations IAM role (empty if not created)."
  value       = length(aws_iam_role.control_tower_config_aggregator) > 0 ? aws_iam_role.control_tower_config_aggregator[0].arn : ""
}

output "backup_admin_account_id" {
  description = "AWS account ID of the Backup Administrator account (empty if not created)."
  value       = length(aws_organizations_account.backup_admin) > 0 ? aws_organizations_account.backup_admin[0].id : ""
}

output "backup_central_account_id" {
  description = "AWS account ID of the Central Backup account (empty if not created)."
  value       = length(aws_organizations_account.backup_central) > 0 ? aws_organizations_account.backup_central[0].id : ""
}
