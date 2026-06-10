output "regional_nat_gateway_id" {
  description = "ID of the regional NAT gateway. Used as the target of the private route table's default route."
  value       = aws_nat_gateway.this.id
}

output "route_table_id" {
  description = "ID of the route table automatically created by the regional NAT gateway. Spoke-CIDR -> TGW return routes must be added here so the NAT can route reply packets back to spoke VPCs through the TGW."
  value       = aws_nat_gateway.this.route_table_id
}
