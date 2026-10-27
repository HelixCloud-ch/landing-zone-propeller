output "fqdn" {
  description = "Fully qualified name of the record, without the trailing dot."
  value       = aws_route53_record.this.fqdn
}
