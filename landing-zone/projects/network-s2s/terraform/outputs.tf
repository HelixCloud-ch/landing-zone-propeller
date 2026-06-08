output "customer_gateway_ids" {
  description = "Map of customer gateway IP to customer gateway ID."
  value       = { for ip, cgw in aws_customer_gateway.this : ip => cgw.id }
}

output "vpn_connection_ids" {
  description = "Map of customer gateway IP to VPN connection ID."
  value       = { for ip, vpn in aws_vpn_connection.this : ip => vpn.id }
}

output "vpn_attachment_ids" {
  description = "Map of customer gateway IP to Transit Gateway VPN attachment ID."
  value       = { for ip, vpn in aws_vpn_connection.this : ip => vpn.transit_gateway_attachment_id }
}

output "tunnel_details" {
  description = "VPN tunnel details for each connection (public IPs, inside addresses, pre-shared keys). Sensitive."
  sensitive   = true
  value = {
    for ip, vpn in aws_vpn_connection.this : ip => {
      tunnel1_address            = vpn.tunnel1_address
      tunnel1_cgw_inside_address = vpn.tunnel1_cgw_inside_address
      tunnel1_vgw_inside_address = vpn.tunnel1_vgw_inside_address
      tunnel1_preshared_key      = vpn.tunnel1_preshared_key
      tunnel2_address            = vpn.tunnel2_address
      tunnel2_cgw_inside_address = vpn.tunnel2_cgw_inside_address
      tunnel2_vgw_inside_address = vpn.tunnel2_vgw_inside_address
      tunnel2_preshared_key      = vpn.tunnel2_preshared_key
    }
  }
}
