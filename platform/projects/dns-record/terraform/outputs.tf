output "fqdn" {
  description = "Fully qualified name of the published record, without the trailing dot."
  value       = module.dns_record.fqdn
}
