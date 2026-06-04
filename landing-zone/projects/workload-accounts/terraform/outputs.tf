output "account_ids" {
  description = "Map of account name to account ID."
  value       = { for name, acct in module.accounts : name => acct.account_id }
}
