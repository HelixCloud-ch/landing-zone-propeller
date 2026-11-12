locals {
  created_vgws = { for k, g in var.vpn_gateways : k => g if g.vpc_id != null }

  vgw_ids = {
    for k, g in var.vpn_gateways :
    k => g.vpn_gateway_id != null ? g.vpn_gateway_id : aws_vpn_gateway.this[k].id
  }

  vgw_propagations = merge([
    for k, g in var.vpn_gateways : {
      for rt in g.route_table_ids : "${k}/${rt}" => { vgw_key = k, route_table_id = rt }
    }
  ]...)

  connection_transit_gateway_ids = {
    for k, c in var.connections :
    k => c.transit_gateway_id != null ? c.transit_gateway_id : var.transit_gateway_id
  }

  connection_target_types = {
    for k, c in var.connections :
    k => (
      c.unattached ? "none" : (
        c.vpn_gateway_key != null ? "vgw" : (
          local.connection_transit_gateway_ids[k] != null ? "tgw" : "none"
        )
      )
    )
  }

  connection_target_gateway_ids = {
    for k, c in var.connections :
    k => (
      local.connection_target_types[k] == "tgw" ? local.connection_transit_gateway_ids[k] : (
        local.connection_target_types[k] == "vgw" ? local.vgw_ids[c.vpn_gateway_key] : null
      )
    )
  }

  connection_customer_gateway_ids = {
    for k, c in var.connections :
    k => c.customer_gateway_id != null ? c.customer_gateway_id : aws_customer_gateway.this[c.customer_gateway_key].id
  }
}
