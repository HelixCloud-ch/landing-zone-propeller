resource "aws_route_table" "this" {
  for_each = var.route_tables

  vpc_id = var.vpc_id

  tags = {
    Name = each.value.name
  }
}

resource "aws_route_table_association" "this" {
  for_each = var.associations

  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.this[each.value.route_table_key].id
}

# Single-route resources (no inline blocks in aws_route_table) so adding a route
# later never rewrites an existing one.
resource "aws_route" "this" {
  for_each = var.routes

  route_table_id         = aws_route_table.this[each.value.route_table_key].id
  destination_cidr_block = each.value.destination_cidr_block

  carrier_gateway_id        = each.value.carrier_gateway_id
  core_network_arn          = each.value.core_network_arn
  egress_only_gateway_id    = each.value.egress_only_gateway_id
  gateway_id                = each.value.gateway_id
  local_gateway_id          = each.value.local_gateway_id
  nat_gateway_id            = each.value.nat_gateway_id
  network_interface_id      = each.value.network_interface_id
  transit_gateway_id        = each.value.transit_gateway_id
  vpc_endpoint_id           = each.value.vpc_endpoint_id
  vpc_peering_connection_id = each.value.vpc_peering_connection_id
}
