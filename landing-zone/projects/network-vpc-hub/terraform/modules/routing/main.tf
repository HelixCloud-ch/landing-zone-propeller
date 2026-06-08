locals {
  # Tiers that actually have subnets get a route table. Tier names and list
  # lengths are known at plan time (driven by var.tiers and az_count), so these
  # keys are plan-stable even though the subnet IDs inside are not.
  active_tiers = { for tier, subnets in var.subnets_by_tier : tier => subnets if length(subnets) > 0 }

  # Per-subnet associations keyed by a static "<tier>-<index>" key. The key must
  # be plan-known (subnet IDs are not), so we use the tier name and the list
  # index; the unknown subnet ID lives in the value.
  associations = merge([
    for tier, subnets in local.active_tiers : {
      for idx, s in subnets : "${tier}-${idx}" => {
        subnet_id = s.id
        tier      = tier
      }
    }
  ]...)

  # Route-creation gates use only plan-known inputs (booleans and tier presence),
  # never `id != null`, which would be unknown until apply.
  create_public_route  = var.internet_gateway_enabled && contains(keys(local.active_tiers), var.public_tier)
  create_private_route = contains(keys(local.active_tiers), var.private_tier)
}

resource "aws_route_table" "this" {
  for_each = local.active_tiers

  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-${each.key}-rt"
  }
}

resource "aws_route_table_association" "this" {
  for_each = local.associations

  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.this[each.value.tier].id
}

# Public tier egress to the internet. Single-route resource (no inline route
# blocks) so sibling projects can add routes to the same table later.
resource "aws_route" "public_internet" {
  count = local.create_public_route ? 1 : 0

  route_table_id         = aws_route_table.this[var.public_tier].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = var.igw_id
}

# Private tier egress via the regional NAT gateway.
resource "aws_route" "private_nat" {
  count = local.create_private_route ? 1 : 0

  route_table_id         = aws_route_table.this[var.private_tier].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.regional_nat_gateway_id
}
