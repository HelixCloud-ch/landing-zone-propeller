output "account_id" {
  description = "AWS account ID of the newly provisioned account, extracted from the Service Catalog provisioned product outputs."
  value = one([
    for o in aws_servicecatalog_provisioned_product.this.outputs : o.value
    if o.key == "AccountId"
  ])
}

output "provisioned_product_id" {
  description = "Service Catalog provisioned product ID. Useful for ad-hoc operations like update-provisioned-product on artifact bumps."
  value       = aws_servicecatalog_provisioned_product.this.id
}

output "managed_organizational_unit" {
  description = "The ManagedOrganizationalUnit value that was passed to Account Factory (\"<name> (<id>)\")."
  value       = local.managed_organizational_unit
}
