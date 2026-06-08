output "tgw_route_table_id" {
  description = "ID of the TGW route table this project owns."
  value       = aws_ec2_transit_gateway_route_table.main.id
}

output "hub_attachment_id" {
  description = "ID of the hub VPC TGW attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

output "onprem_cidrs" {
  description = "On-premises IPv4 CIDR blocks routed through the Site-to-Site VPN. Consumed by downstream projects (e.g. network-resolver SG rules, network-firewall policy)."
  value       = var.onprem_cidrs
}
