output "arn" {
  description = "Certificate ARN. With wait_for_validation it is known only after issuance."
  value       = var.wait_for_validation ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "domain_name" {
  description = "Primary domain name."
  value       = aws_acm_certificate.this.domain_name
}

output "status" {
  description = "Status at the last refresh. On the run that waits it can still say PENDING_VALIDATION. Use arn."
  value       = aws_acm_certificate.this.status
}

output "validation_records" {
  description = "DNS validation records, one per distinct record name. Empty for EMAIL and private CA."
  value       = [for k in sort(keys(local.validation_by_name)) : local.validation_by_name[k][0]]
}

output "validation_records_by_domain" {
  description = "DNS validation record (name, type, value) by certificate domain name. Empty unless DNS."
  value       = local.validation_by_domain
}
