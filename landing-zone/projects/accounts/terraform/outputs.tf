output "account_ids" {
  description = "Map of account name to account ID."
  value       = { for name, acct in module.accounts : name => acct.account_id }
}

output "provisioned_product_ids" {
  description = "Map of account name to Service Catalog provisioned product ID."
  value       = { for name, acct in module.accounts : name => acct.provisioned_product_id }
}
