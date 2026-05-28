output "account_id" {
  description = "AWS account ID of the Network account."
  value       = module.account.account_id
}

output "provisioned_product_id" {
  description = "Service Catalog provisioned product ID for the Network account."
  value       = module.account.provisioned_product_id
}
