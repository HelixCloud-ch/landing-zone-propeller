# ── Hub VPC TGW attachment ───────────────────────────────────────────────────
# Attaches the hub VPC to the TGW using the dormant tgw-tier subnets provisioned
# by network-vpc-hub. Default association/propagation are disabled — this project
# manages both explicitly (the TGW has default_route_table_association/propagation
# = "disable").
resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  subnet_ids         = local.hub_tgw_subnet_ids
  transit_gateway_id = var.tgw_id
  vpc_id             = var.hub_vpc_id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${var.name_prefix}-hub-attach"
  }
}

# ── TGW route table ──────────────────────────────────────────────────────────
# Single route table for the current topology (hub + VPN on one table).
# Per-segment tables (Spokes/Hub split) are a later extension.
resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = var.tgw_id

  tags = {
    Name = "${var.name_prefix}-rt"
  }
}

# ── Associations ─────────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  for_each = local.vpn_attachment_ids

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# ── TGW routes ───────────────────────────────────────────────────────────────
# Hub VPC CIDR → hub attachment (static, propagation disabled on the TGW).
resource "aws_ec2_transit_gateway_route" "hub_cidr" {
  destination_cidr_block         = var.hub_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# On-prem CIDRs → VPN attachment (one per cidr × peer pair).
resource "aws_ec2_transit_gateway_route" "onprem" {
  for_each = local.onprem_routes

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# Spoke internet egress: default route on the TGW route table → hub attachment,
# so spoke traffic bound for the internet is sent into the hub VPC (where the
# tgw-tier 0/0 → NAT route below takes it to the regional NAT). Opt-in via the
# same toggle as the VPC-side egress route.
resource "aws_ec2_transit_gateway_route" "spoke_egress_default" {
  count = var.enable_spoke_egress ? 1 : 0

  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# ── Hub VPC return routes ────────────────────────────────────────────────────
# On-prem CIDR → TGW on each enabled hub tier's route table. Single-route
# aws_route (no inline route blocks) so network-vpc-hub keeps owning its 0/0 on
# the same tables. The precondition turns a missing tier into a clear error
# instead of a cryptic "Invalid index" on the route_table_ids lookup.
resource "aws_route" "hub_to_onprem" {
  for_each = local.onprem_return_routes

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.tgw_id

  lifecycle {
    precondition {
      condition     = alltrue([for tier in var.onprem_return_route_tiers : contains(keys(local.hub_route_table_ids), tier)])
      error_message = "Every tier in onprem_return_route_tiers must exist in the hub's route_table_ids. Requested: ${jsonencode(var.onprem_return_route_tiers)}; available tiers: ${jsonencode(keys(local.hub_route_table_ids))}. Enable the tier in network-vpc-hub or adjust onprem_return_route_tiers."
    }
  }
}

# ── Spoke internet egress via the hub NAT ────────────────────────────────────
# Spoke traffic enters the hub VPC through the TGW attachment, so it follows the
# attachment tier's subnet route table (spoke_egress_tier, default "tgw"). A
# 0.0.0.0/0 there sends internet-bound traffic to the regional NAT gateway,
# which egresses via the IGW (the RNAT's own route table handles NAT -> IGW).
# Opt-in; the hub project keeps owning the private tier's own 0/0. See AWS
# centralized-egress guidance.
resource "aws_route" "spoke_egress" {
  count = var.enable_spoke_egress ? 1 : 0

  route_table_id         = local.hub_route_table_ids[var.spoke_egress_tier]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.regional_nat_gateway_id

  lifecycle {
    precondition {
      condition     = contains(keys(local.hub_route_table_ids), var.spoke_egress_tier)
      error_message = "enable_spoke_egress requires the '${var.spoke_egress_tier}' tier in the hub's route_table_ids. Available tiers: ${jsonencode(keys(local.hub_route_table_ids))}. Enable it in network-vpc-hub or set spoke_egress_tier."
    }
    precondition {
      condition     = var.regional_nat_gateway_id != ""
      error_message = "enable_spoke_egress requires regional_nat_gateway_id (from /network.nat.regional_id)."
    }
  }
}
