output "provisioned_product_id" {
  description = "Service Catalog provisioned product ID."
  value       = aws_servicecatalog_provisioned_product.this.id
}

output "provisioned_product_status" {
  description = "Status of the provisioned product (AVAILABLE, ERROR, TAINTED, etc.)."
  value       = aws_servicecatalog_provisioned_product.this.status
}
