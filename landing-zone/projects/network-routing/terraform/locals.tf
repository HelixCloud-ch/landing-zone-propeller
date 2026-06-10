locals {
  # Aliases for readability — these inputs arrive as native HCL types (the engine
  # passes structured -var values as JSON, which Terraform parses against the
  # variable's declared type). Empty defaults are handled by the variable defaults.
  vpn_attachment_ids  = var.vpn_attachment_ids
  hub_route_table_ids = var.hub_route_table_ids
  hub_tgw_subnet_ids  = var.hub_tgw_subnet_ids

  # On-prem CIDR × VPN attachment product. Static routes are required because
  # network-s2s sets static_routes_only = true (no BGP propagation). Keyed by
  # "<cidr>@<peer_ip>" so multiple attachments (HA) each get every on-prem route.
  onprem_routes = merge([
    for peer_ip, attach_id in local.vpn_attachment_ids : {
      for cidr in var.onprem_cidrs :
      "${cidr}@${peer_ip}" => {
        cidr          = cidr
        attachment_id = attach_id
      }
    }
  ]...)

  # On-prem return routes: one per (tier, cidr). Keyed by "<tier>@<cidr>" so each
  # enabled hub tier's route table gets every on-prem CIDR pointed at the TGW.
  onprem_return_routes = merge([
    for tier in var.onprem_return_route_tiers : {
      for cidr in var.onprem_cidrs :
      "${tier}@${cidr}" => {
        route_table_id = local.hub_route_table_ids[tier]
        cidr           = cidr
      }
    }
  ]...)
}
