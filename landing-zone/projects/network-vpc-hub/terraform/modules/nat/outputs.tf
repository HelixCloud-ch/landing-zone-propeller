output "regional_nat_gateway_id" {
  description = "ID of the regional NAT gateway. Used as the target of the private route table's default route."
  value       = aws_nat_gateway.this.id
}
