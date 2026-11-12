resource "aws_vpn_gateway" "this" {
  for_each = local.created_vgws

  vpc_id          = each.value.vpc_id
  amazon_side_asn = each.value.amazon_side_asn

  tags = {
    Name = coalesce(each.value.name, each.key)
  }
}

resource "aws_vpn_gateway_route_propagation" "this" {
  for_each = local.vgw_propagations

  vpn_gateway_id = local.vgw_ids[each.value.vgw_key]
  route_table_id = each.value.route_table_id
}

resource "aws_customer_gateway" "this" {
  for_each = var.customer_gateways

  type             = "ipsec.1"
  ip_address       = each.value.ip_address
  certificate_arn  = each.value.certificate_arn
  device_name      = each.value.device_name
  bgp_asn          = each.value.bgp_asn <= 2147483647 ? each.value.bgp_asn : null
  bgp_asn_extended = each.value.bgp_asn > 2147483647 ? each.value.bgp_asn : null

  tags = {
    Name = coalesce(each.value.name, each.key)
  }
}

module "connection" {
  source   = "../../../shared/modules/site-to-site-vpn-connection"
  for_each = var.connections

  name                     = coalesce(each.value.name, each.key)
  customer_gateway_id      = local.connection_customer_gateway_ids[each.key]
  target_type              = local.connection_target_types[each.key]
  target_gateway_id        = local.connection_target_gateway_ids[each.key]
  routing                  = each.value.routing
  static_routes            = each.value.static_routes
  tunnel_bandwidth         = each.value.tunnel_bandwidth
  enable_acceleration      = each.value.enable_acceleration
  local_ipv4_network_cidr  = each.value.local_ipv4_network_cidr
  remote_ipv4_network_cidr = each.value.remote_ipv4_network_cidr
  preshared_key_storage    = each.value.preshared_key_storage
  log_group_arn            = each.value.log_group_arn
  bgp_log_group_arn        = each.value.bgp_log_group_arn
  tunnel_options           = each.value.tunnel_options
  tunnel1_inside_cidr      = each.value.tunnel1_inside_cidr
  tunnel2_inside_cidr      = each.value.tunnel2_inside_cidr
}
