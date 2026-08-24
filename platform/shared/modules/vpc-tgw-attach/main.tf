# transit_gateway_default_route_table_association and _propagation are
# intentionally omitted: per the resource docs, they "cannot be configured or
# perform drift detection with Resource Access Manager shared EC2 Transit
# Gateways". The TGW owner (network-spokes in the network account) is the
# single owner of associations and propagations. See ADR-009.
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.tgw_id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids

  dns_support  = "enable"
  ipv6_support = "disable"

  tags = {
    Name = "${var.name_prefix}-tgw-attach"
  }
}
