output "fqdns" {
  description = "Published record FQDNs (without trailing dot), keyed by the same ids as the records input."
  value       = { for k, m in module.dns_record : k => m.fqdn }
}
