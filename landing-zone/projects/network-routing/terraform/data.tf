locals {
  # Complex inputs arrive as JSON strings from the engine (_write_outputs uses
  # json.dumps for list/dict values; _var_args passes them as plain strings).
  # Decode here so the rest of the config works with native HCL types.
  vpn_attachment_ids  = var.vpn_attachment_ids == "" ? {} : jsondecode(var.vpn_attachment_ids)
  hub_route_table_ids = jsondecode(var.hub_route_table_ids)
  hub_tgw_subnet_ids  = jsondecode(var.hub_tgw_subnet_ids)

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
}
