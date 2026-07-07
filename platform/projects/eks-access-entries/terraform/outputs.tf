output "access_entry_arns" {
  description = "Map of entry key to EKS access entry ARN. SSO entries are prefixed with 'sso_', direct entries with 'direct_'. SSO entries whose role was not found in this account are omitted."
  value = {
    for k, v in aws_eks_access_entry.this : k => v.access_entry_arn
  }
}

output "principal_arns" {
  description = "Map of entry key to the IAM principal ARN registered as an access entry."
  value = {
    for k, v in local.all_entries : k => v.principal_arn
  }
}
