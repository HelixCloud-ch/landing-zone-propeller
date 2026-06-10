locals {
  # Aliases for readability — these inputs arrive as native HCL types (the engine
  # passes structured -var values as JSON, which Terraform parses against the
  # variable's declared type).
  spokes             = var.spokes
  vpn_attachment_ids = var.vpn_attachment_ids
  onprem_cidrs       = var.onprem_cidrs
  segments           = toset(var.segments)

  # On-prem reachability targets the VPN attachment. network-s2s runs a single
  # static-routed connection in the current topology, so the first attachment is
  # the target; empty when network-s2s is absent.
  vpn_attachment_id = length(local.vpn_attachment_ids) > 0 ? values(local.vpn_attachment_ids)[0] : ""

  # Shared-destination routes — hub. For each spoke whose allowed_destinations
  # names "hub", emit one route in that spoke's segment table: hub CIDR -> hub
  # attachment. Keyed "<friendly>@hub".
  hub_routes = {
    for name, s in local.spokes :
    "${name}@hub" => {
      segment       = s.segment
      cidr          = var.hub_vpc_cidr
      attachment_id = var.hub_attachment_id
    } if contains(s.allowed_destinations, "hub")
  }

  # Shared-destination routes — on-prem. For each spoke whose allowed_destinations
  # names "onprem", emit one route per on-prem CIDR in that spoke's segment table:
  # onprem CIDR -> VPN attachment. Keyed "<friendly>@onprem@<cidr>".
  onprem_routes = merge([
    for name, s in local.spokes : {
      for cidr in local.onprem_cidrs :
      "${name}@onprem@${cidr}" => {
        segment       = s.segment
        cidr          = cidr
        attachment_id = local.vpn_attachment_id
      }
    } if contains(s.allowed_destinations, "onprem")
  ]...)

  # Peer (spoke-to-spoke) routes. For each spoke, for each allowed destination
  # that names another registry entry, emit one route per peer CIDR in this
  # spoke's segment table: peer CIDR -> peer attachment. Directional only — mutual
  # reachability requires the peer to name this spoke too (no implicit symmetry).
  # Unknown destination names are filtered out (contains check) so they produce
  # no route. Keyed "<friendly>@<peer>@<cidr>".
  peer_routes = merge([
    for name, s in local.spokes : {
      for pair in flatten([
        for dest in s.allowed_destinations : [
          for cidr in try(local.spokes[dest].cidrs, []) : { dest = dest, cidr = cidr }
        ] if contains(keys(local.spokes), dest)
      ]) :
      "${name}@${pair.dest}@${pair.cidr}" => {
        segment       = s.segment
        cidr          = pair.cidr
        attachment_id = aws_ec2_transit_gateway_vpc_attachment_accepter.spoke[pair.dest].id
      }
    }
  ]...)

  # Hub return routes — written into the 'main' TGW route table (owned by
  # network-routing) so the hub can return or initiate traffic to accepted spokes.
  # One route per spoke CIDR, for every spoke that declared "hub" reachability.
  # Keyed "<friendly>@return@<cidr>".
  # Only populated when hub_tgw_route_table_id is provided.
  hub_return_routes = var.hub_tgw_route_table_id != "" ? merge([
    for name, s in local.spokes : {
      for cidr in s.cidrs :
      "${name}@return@${cidr}" => {
        cidr          = cidr
        attachment_id = aws_ec2_transit_gateway_vpc_attachment_accepter.spoke[name].id
      }
    } if contains(s.allowed_destinations, "hub")
  ]...) : {}

  # Hub VPC return routes — written into the hub's tgw-tier VPC route table
  # (owned by network-vpc-hub) so the hub NAT can return packets to spoke VPCs.
  # Without these, NAT reply packets have no route back to spoke CIDRs and are
  # dropped. One aws_route per spoke CIDR, destination -> TGW. Only emitted when
  # hub_vpc_route_table_ids contains the "tgw" key.
  hub_vpc_tgw_rt_id = lookup(var.hub_vpc_route_table_ids, "tgw", "")

  hub_vpc_return_routes = local.hub_vpc_tgw_rt_id != "" ? merge([
    for name, s in local.spokes : {
      for cidr in s.cidrs :
      "${name}@vpc-return@${cidr}" => {
        cidr = cidr
      }
    } if contains(s.allowed_destinations, "hub")
  ]...) : {}
}
