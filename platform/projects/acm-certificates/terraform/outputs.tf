output "arns" {
  description = "Certificate ARN by certificate key. Known after issuance when wait_for_validation is true."
  value = {
    for k, c in module.certificate :
    k => try(aws_acm_certificate_validation.this[k].certificate_arn, c.arn)
  }
}

output "domain_names" {
  description = "Primary domain name by certificate key."
  value       = { for k, c in module.certificate : k => c.domain_name }
}

output "statuses" {
  description = "Status at the last refresh, by key. On the run that waits it can still say PENDING_VALIDATION. Use arns."
  value       = { for k, c in module.certificate : k => c.status }
}

output "validation_records" {
  description = "DNS validation records (name, type, value) by certificate key."
  value       = { for k, c in module.certificate : k => c.validation_records }
}

output "validation_record_fqdns" {
  description = "FQDNs of the validation records this project created, by certificate key. Empty without validation_zone_id."
  value       = local.created_record_fqdns
}

output "dns_validation_records" {
  description = "Validation records across all certificates, one per record name, as the dns-record `records` input."
  value       = local.validation_records
}
