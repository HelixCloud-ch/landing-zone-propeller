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

# ── Hub VPC return route ─────────────────────────────────────────────────────
# Private-tier route table: on-prem CIDR → TGW. Single-route aws_route (no
# inline route blocks) so network-vpc-hub keeps owning its 0/0 on the same RT.
resource "aws_route" "hub_to_onprem" {
  for_each = toset(var.onprem_cidrs)

  route_table_id         = local.hub_route_table_ids["private"]
  destination_cidr_block = each.value
  transit_gateway_id     = var.tgw_id
}
