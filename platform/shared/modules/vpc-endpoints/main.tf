# A single resource block: aws_vpc_endpoint accepts both Interface- and
# Gateway-specific arguments and ignores whichever don't apply to the
# resolved vpc_endpoint_type, so there is no need to split Interface and
# Gateway into separate resource blocks.
#
# The module creates no security groups. Interface endpoints attach whatever
# security_group_ids the caller supplies — same convention as every other
# shared module in this framework (e.g. rds-postgresql's security_group_id).

resource "aws_vpc_endpoint" "this" {
  for_each = var.endpoints

  vpc_id            = var.vpc_id
  vpc_endpoint_type = each.value.type
  service_name      = data.aws_vpc_endpoint_service.this[each.key].service_name
  policy            = local.effective_policy[each.key]

  # Interface-only arguments (null for Gateway endpoints, which AWS ignores).
  subnet_ids          = each.value.type == "Interface" ? each.value.subnet_ids : null
  security_group_ids  = each.value.type == "Interface" ? each.value.security_group_ids : null
  private_dns_enabled = each.value.type == "Interface" ? each.value.private_dns_enabled : null

  # Gateway-only argument.
  route_table_ids = each.value.type == "Gateway" ? each.value.route_table_ids : null

  tags = {
    Name = coalesce(each.value.name, each.key)
  }
}
