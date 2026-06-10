# ── Spoke attachment accepters ───────────────────────────────────────────────
# Adopt each pending cross-account VPC attachment into network-account management
# and give it the registry key as its friendly Name. The default-route-table
# association/propagation arguments default to true in the provider and are forced
# false here: segmentation is explicit only — every attachment is placed in a
# governance-chosen segment, never the TGW defaults.
resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "spoke" {
  for_each = local.spokes

  transit_gateway_attachment_id = each.value.attachment_id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = each.key
  }
}

# ── Segment route tables ──────────────────────────────────────────────────────
# One TGW route table per governance-defined segment. This project is the single
# owner of every segment table. Names are arbitrary (governance policy); no name
# is reserved. An empty var.segments creates zero tables.
resource "aws_ec2_transit_gateway_route_table" "segment" {
  for_each = local.segments

  transit_gateway_id = var.tgw_id

  tags = {
    Name = "${var.name_prefix}-seg-${each.key}"
  }

  lifecycle {
    precondition {
      condition     = length(var.segments) <= 20
      error_message = "segments declares ${length(var.segments)} route tables, exceeding the default TGW route-table quota of 20. Request a quota increase or reduce the segment count."
    }
  }
}

# ── Associations ──────────────────────────────────────────────────────────────
# Place each accepted attachment into its declared segment table (1:1). The
# precondition validates the segment reference before the association is created,
# turning an undeclared segment into a clear error instead of an index failure.
resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = local.spokes

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment_accepter.spoke[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segment[each.value.segment].id

  lifecycle {
    precondition {
      condition     = contains(var.segments, each.value.segment)
      error_message = "Spoke '${each.key}' references segment '${each.value.segment}', which is not declared in var.segments. Declared: ${jsonencode(var.segments)}."
    }
  }
}

# ── Shared-destination routes: hub ──────────────────────────────────────────────
# Per-segment static route hub CIDR -> hub attachment, for spokes that declared
# "hub". Single-route resource (no propagation); the target is the hub attachment
# owned by network-routing, but the route lives in a segment table owned here.
resource "aws_ec2_transit_gateway_route" "hub" {
  for_each = local.hub_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segment[each.value.segment].id

  lifecycle {
    precondition {
      condition     = var.hub_attachment_id != "" && var.hub_vpc_cidr != ""
      error_message = "A spoke requests 'hub' reachability but hub_attachment_id/hub_vpc_cidr are unset. Wire network-routing.hub_attachment_id and /network.vpc.cidr on the network-spokes step."
    }
  }
}

# ── Internet egress route: 0.0.0.0/0 -> hub (per segment) ──────────────────────
# One default-route per segment table for segments that contain at least one spoke
# with "hub" reachability. This is the critical TGW-side piece of the centralised-
# egress pattern: spoke -> TGW segment table (0.0.0.0/0 here) -> hub attachment ->
# hub VPC NAT Gateway -> internet. Without this route the TGW drops packets whose
# destination is not explicitly covered by another route in the segment table.
# Gated on var.enable_segment_internet_egress (default true). Requires
# hub_attachment_id to be set (enforced by precondition at plan time).
resource "aws_ec2_transit_gateway_route" "segment_internet_egress" {
  for_each = local.segment_internet_egress_routes

  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segment[each.value.segment].id

  lifecycle {
    precondition {
      condition     = var.hub_attachment_id != ""
      error_message = "enable_segment_internet_egress is true but hub_attachment_id is empty. Wire network-routing.hub_attachment_id on the network-spokes step, or set enable_segment_internet_egress = false."
    }
  }
}

# ── Shared-destination routes: on-prem ──────────────────────────────────────────
# Per-segment static route onprem CIDR -> VPN attachment, for spokes that declared
# "onprem". One per (spoke, onprem CIDR).
resource "aws_ec2_transit_gateway_route" "onprem" {
  for_each = local.onprem_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segment[each.value.segment].id

  lifecycle {
    precondition {
      condition     = local.vpn_attachment_id != ""
      error_message = "A spoke requests 'onprem' reachability but vpn_attachment_ids is empty. Deploy network-s2s and wire network-s2s.vpn_attachment_ids on the network-spokes step."
    }
  }
}

# ── Hub return routes (in main, owned by network-routing) ──────────────────────
# For each spoke that declared "hub" reachability, write spoke-CIDR -> spoke-attachment
# into the hub's TGW route table (main). This is what allows the hub to return
# traffic (NAT reply packets, or hub-initiated connections) back to the spoke.
# network-spokes owns these routes because it owns the spoke lifecycle — adding a
# spoke creates the return path, removing it destroys it, atomically.
# Gated on hub_tgw_route_table_id being set; the route table itself is not owned here.
resource "aws_ec2_transit_gateway_route" "hub_return" {
  for_each = local.hub_return_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = var.hub_tgw_route_table_id

  lifecycle {
    precondition {
      condition     = var.hub_tgw_route_table_id != ""
      error_message = "hub_tgw_route_table_id must be set to write hub return routes. Wire network-routing.tgw_route_table_id on the network-spokes step."
    }
  }
}

# ── Hub NAT return routes (in regional NAT's own route table) ──────────────────
# The regional NAT gateway has its own route table (separate from the hub's subnet
# RTs). When the NAT translates a packet back to a spoke IP, it looks up the
# destination in THIS table. Without a spoke-CIDR -> TGW route here, the NAT
# drops the reply packet. network-spokes owns these routes because it owns the
# spoke lifecycle and knows all spoke CIDRs. The NAT route table itself is owned
# by network-vpc-hub; we only add individual aws_route resources (no inline blocks).
resource "aws_route" "hub_nat_return" {
  for_each = local.hub_nat_return_routes

  route_table_id         = var.hub_nat_route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.tgw_id

  lifecycle {
    precondition {
      condition     = var.hub_nat_route_table_id != ""
      error_message = "hub_nat_route_table_id must be set to write hub NAT return routes. Wire network-vpc-hub.regional_nat_route_table_id on the network-spokes step."
    }
  }
}

# ── Hub VPC return routes (in hub tgw-tier RT, owned by network-vpc-hub) ───────
# For each spoke that declared "hub" reachability, write spoke-CIDR -> TGW into
# the hub VPC's tgw-tier route table. This is what allows the hub NAT to return
# reply packets to spoke VPCs — without it, NAT has no route back for spoke CIDRs.
# network-spokes owns these routes because it owns the spoke lifecycle and knows
# all spoke CIDRs. The route table itself is owned by network-vpc-hub; we only
# add individual aws_route resources (no inline blocks) to avoid state conflicts.
resource "aws_route" "hub_vpc_return" {
  for_each = local.hub_vpc_return_routes

  route_table_id         = local.hub_vpc_tgw_rt_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.tgw_id

  lifecycle {
    precondition {
      condition     = local.hub_vpc_tgw_rt_id != ""
      error_message = "hub_vpc_route_table_ids must contain a 'tgw' key to write hub VPC return routes. Wire network-vpc-hub.route_table_ids on the network-spokes step."
    }
  }
}

# Per-segment static route peer CIDR -> peer attachment, written only in the
# declaring spoke's segment table. Directional: mutual reachability requires both
# spokes to name each other (no implicit symmetry — isolation by default).
resource "aws_ec2_transit_gateway_route" "peer" {
  for_each = local.peer_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segment[each.value.segment].id
}
