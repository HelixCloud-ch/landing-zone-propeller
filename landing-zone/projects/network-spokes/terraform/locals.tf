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

  # Shared-destination routes — hub. One route per segment (not per spoke):
  # hub CIDR -> hub attachment. Multiple spokes in the same segment all require
  # the same route; keying by spoke would cause RouteAlreadyExists on the second
  # spoke. Deduplicated by collecting the distinct segments that need a hub route,
  # then emitting one entry per segment. Keyed "<segment>@hub".
  hub_routes = {
    for seg in distinct([
      for name, s in local.spokes : s.segment
      if contains(s.allowed_destinations, "hub")
    ]) :
    "${seg}@hub" => {
      segment       = seg
      cidr          = var.hub_vpc_cidr
      attachment_id = var.hub_attachment_id
    }
  }

  # Shared-destination routes — on-prem. One route per (segment, on-prem CIDR):
  # onprem CIDR -> VPN attachment. Same deduplication rationale as hub_routes —
  # multiple spokes in the same segment would otherwise collide on the same
  # destination CIDR. Keyed "<segment>@onprem@<cidr>".
  onprem_routes = {
    for pair in distinct(flatten([
      for name, s in local.spokes : [
        for cidr in local.onprem_cidrs : {
          segment = s.segment
          cidr    = cidr
        }
      ] if contains(s.allowed_destinations, "onprem")
    ])) :
    "${pair.segment}@onprem@${pair.cidr}" => {
      segment       = pair.segment
      cidr          = pair.cidr
      attachment_id = local.vpn_attachment_id
    }
  }

  # Peer (spoke-to-spoke) routes: peer CIDR -> peer attachment, written into the
  # segment's route table. Because every spoke in a segment shares one route
  # table, a peer route is a property of the (segment, peer) pair, not of the
  # source spoke — so the map is keyed "<segment>@<peer>@<cidr>". Multiple spokes
  # in the same segment naming the same peer therefore collapse to one route via
  # merge() (identical value), instead of colliding on RouteAlreadyExists.
  #
  # Keys use only plan-time-known values (segment/dest/cidr); the known-after-apply
  # attachment_id stays in the value, so for_each stays resolvable at plan time.
  # Unknown destination names are filtered out (contains check) so they emit no
  # route.
  #
  # NOTE: within a single segment table reachability is shared by all associated
  # spokes — per-spoke allowed_destinations differentiate reachability only ACROSS
  # segments, not between members of the same segment.
  peer_routes = merge([
    for name, s in local.spokes : {
      for pair in flatten([
        for dest in s.allowed_destinations : [
          for cidr in try(local.spokes[dest].cidrs, []) : { dest = dest, cidr = cidr }
        ] if contains(keys(local.spokes), dest)
      ]) :
      "${s.segment}@${pair.dest}@${pair.cidr}" => {
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
  #
  # IMPORTANT: spoke CIDRs that fall within the hub VPC CIDR are already covered
  # by the VPC's implicit "local" route. AWS rejects any attempt to add a TGW
  # route for a destination that is equal to or more specific than the VPC's own
  # CIDR blocks (InvalidParameterValue). These CIDRs are excluded here.
  # This is the normal case when the hub uses a large /16 CIDR that encompasses
  # all spoke allocations.
  hub_vpc_tgw_rt_id = lookup(var.hub_vpc_route_table_ids, "tgw", "")

  hub_vpc_return_routes = local.hub_vpc_tgw_rt_id != "" ? merge([
    for name, s in local.spokes : {
      for cidr in s.cidrs :
      "${name}@vpc-return@${cidr}" => {
        cidr = cidr
      }
      # Skip CIDRs that are subsets of (or equal to) the hub VPC CIDR. AWS rejects
      # routes whose destination is covered by the VPC's own "local" route
      # (InvalidParameterValue). A spoke CIDR is inside the hub CIDR when both
      # share the same network address at the hub's prefix length — i.e. masking
      # the spoke's network address to the hub's prefix gives back the hub's
      # network address.  cidrhost(hub, 0) and cidrhost(spoke_masked_to_hub, 0)
      # are equal in that case.
      if var.hub_vpc_cidr == "" || cidrhost(var.hub_vpc_cidr, 0) != cidrhost(
        format("%s/%s", cidrhost(cidr, 0), split("/", var.hub_vpc_cidr)[1]), 0
      )
    } if contains(s.allowed_destinations, "hub")
  ]...) : {}

  # Internet egress routes — per-segment 0.0.0.0/0 -> hub_attachment_id, written
  # into every segment that contains at least one spoke with "hub" reachability.
  # This is the centralised-egress pattern: spoke -> TGW -> hub VPC -> NAT Gateway.
  # Gated on var.enable_segment_internet_egress; emits one route per segment (not
  # per spoke), so duplicate routes for multiple spokes in the same segment are
  # deduplicated here. Keyed by segment name.
  segment_internet_egress_routes = var.enable_segment_internet_egress ? {
    for seg in distinct([
      for name, s in local.spokes : s.segment
      if contains(s.allowed_destinations, "hub")
    ]) :
    seg => {
      segment       = seg
      attachment_id = var.hub_attachment_id
    }
  } : {}

  # Hub NAT return routes — written into the regional NAT gateway's own route
  # table (rtb-* automatically created by AWS for the regional NAT) so the NAT
  # itself can route reply packets back to spoke VPCs via the TGW. This is the
  # critical missing piece: the NAT uses its own route table for outbound routing,
  # not the subnet RT. One aws_route per spoke CIDR -> TGW.
  #
  # Same exclusion as hub_vpc_return_routes: spoke CIDRs contained within the hub
  # VPC CIDR are already covered by the VPC local route; AWS rejects a TGW route
  # for them.
  hub_nat_return_routes = var.hub_nat_route_table_id != "" ? merge([
    for name, s in local.spokes : {
      for cidr in s.cidrs :
      "${name}@nat-return@${cidr}" => {
        cidr = cidr
      }
      if var.hub_vpc_cidr == "" || cidrhost(var.hub_vpc_cidr, 0) != cidrhost(
        format("%s/%s", cidrhost(cidr, 0), split("/", var.hub_vpc_cidr)[1]), 0
      )
    } if contains(s.allowed_destinations, "hub")
  ]...) : {}
}
