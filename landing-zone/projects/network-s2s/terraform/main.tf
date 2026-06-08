locals {
  # Map of CGW IP to index for stable resource keys
  cgw_map = { for idx, ip in var.customer_gateway_ips : ip => idx }
}

# Customer Gateway(s) — one per on-prem peer IP
resource "aws_customer_gateway" "this" {
  for_each = local.cgw_map

  bgp_asn    = 65000 # Placeholder, not used with static routing
  ip_address = each.key
  type       = "ipsec.1"

  tags = {
    Name = "${var.name_prefix}-cgw-${each.value}"
  }
}

# VPN Connection(s) — one per customer gateway, attached to TGW
# Each VPN connection creates 2 tunnels automatically (AWS default)
# static_routes_only = true: on-prem CIDRs are declared as TGW route table
# entries by the routing project, not via aws_vpn_connection_route (which is
# VGW-only and fails when transit_gateway_id is set).
resource "aws_vpn_connection" "this" {
  for_each = local.cgw_map

  customer_gateway_id = aws_customer_gateway.this[each.key].id
  transit_gateway_id  = var.tgw_id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = {
    Name = "${var.name_prefix}-vpn-${each.value}"
  }
}

