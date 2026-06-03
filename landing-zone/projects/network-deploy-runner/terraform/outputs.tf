output "provisioned_product_id" {
  description = "Service Catalog provisioned product ID for the deploy-runner in the Network account."
  value       = module.deploy_runner.provisioned_product_id
}

output "provisioned_product_status" {
  description = "Status of the Service Catalog provisioned product."
  value       = module.deploy_runner.provisioned_product_status
}
