output "id" {
  description = "ID of the VPN connection."
  value       = aws_vpn_connection.this.id
}

output "arn" {
  description = "ARN of the VPN connection."
  value       = aws_vpn_connection.this.arn
}

output "transit_gateway_attachment_id" {
  description = "ID of the transit gateway VPN attachment. Meaningful only when target_type is tgw."
  value       = aws_vpn_connection.this.transit_gateway_attachment_id
}

output "tunnels" {
  description = "Public addresses, inside addresses and BGP ASN of both tunnels."
  value = {
    tunnel1_address            = aws_vpn_connection.this.tunnel1_address
    tunnel1_cgw_inside_address = aws_vpn_connection.this.tunnel1_cgw_inside_address
    tunnel1_vgw_inside_address = aws_vpn_connection.this.tunnel1_vgw_inside_address
    tunnel1_bgp_asn            = aws_vpn_connection.this.tunnel1_bgp_asn
    tunnel2_address            = aws_vpn_connection.this.tunnel2_address
    tunnel2_cgw_inside_address = aws_vpn_connection.this.tunnel2_cgw_inside_address
    tunnel2_vgw_inside_address = aws_vpn_connection.this.tunnel2_vgw_inside_address
    tunnel2_bgp_asn            = aws_vpn_connection.this.tunnel2_bgp_asn
  }
}

output "preshared_key_arn" {
  description = "ARN of the Secrets Manager secret with the pre-shared keys. Null with Standard storage."
  value       = var.preshared_key_storage == "SecretsManager" ? aws_vpn_connection.this.preshared_key_arn : null
}
