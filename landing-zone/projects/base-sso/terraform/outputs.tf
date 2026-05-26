output "permission_set_arns" {
  description = "ARNs of the four permission sets."
  value = {
    readonly          = aws_ssoadmin_permission_set.readonly.arn
    poweruser         = aws_ssoadmin_permission_set.poweruser.arn
    admin             = aws_ssoadmin_permission_set.admin.arn
    identity_operator = aws_ssoadmin_permission_set.identity_operator.arn
  }
}

output "identity_operators_group_id" {
  description = "Identity Store ID of the aws-identity-operators group."
  value       = local.identity_operators_group_id
}

output "instance_arn" {
  description = "ARN of the IAM Identity Center instance."
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "ID of the Identity Store."
  value       = local.identity_store_id
}
