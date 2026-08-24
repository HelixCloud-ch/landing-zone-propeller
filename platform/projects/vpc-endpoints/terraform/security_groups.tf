# Shared fallback security group for Interface endpoints without their own
# security_group_ids. See the README for the rationale (default all
# ports/protocols, opt-in narrowing via security_group_ports).

locals {
  endpoints_needing_shared_sg = [
    for k, v in var.endpoints : k if v.type == "Interface" && length(v.security_group_ids) == 0
  ]
  create_shared_security_group = length(local.endpoints_needing_shared_sg) > 0
  restrict_shared_sg_ports     = length(var.security_group_ports) > 0

  shared_sg_cidr_rules = local.create_shared_security_group ? (
    local.restrict_shared_sg_ports ? {
      for pair in setproduct(var.security_group_ports, var.security_group_cidrs) :
      "${pair[0]}-${pair[1]}" => { port = pair[0], cidr = pair[1] }
    } : { for cidr in var.security_group_cidrs : cidr => { port = null, cidr = cidr } }
  ) : {}

  shared_sg_source_security_group_rules = local.create_shared_security_group ? (
    local.restrict_shared_sg_ports ? {
      for pair in setproduct(var.security_group_ports, var.security_group_source_security_group_ids) :
      "${pair[0]}-${pair[1]}" => { port = pair[0], source_sg = pair[1] }
    } : { for sg in var.security_group_source_security_group_ids : sg => { port = null, source_sg = sg } }
  ) : {}
}

resource "aws_security_group" "shared" {
  count = local.create_shared_security_group ? 1 : 0
  # checkov:skip=CKV2_AWS_5: attached via module.vpc_endpoints's aws_vpc_endpoint.this[*].security_group_ids (local.endpoints, security_group_ids field); the indirection through count, a local map, and a module boundary is invisible to checkov's static graph.

  name        = var.security_group_name
  description = "Shared security group for VPC interface endpoints in ${var.vpc_id}."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "shared_cidrs" {
  for_each = local.shared_sg_cidr_rules

  security_group_id = aws_security_group.shared[0].id
  ip_protocol       = local.restrict_shared_sg_ports ? var.security_group_protocol : "-1"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  description       = "VPC endpoint access from ${each.value.cidr}${each.value.port != null ? " on port ${each.value.port}" : ""}"
}

resource "aws_vpc_security_group_ingress_rule" "shared_source_security_groups" {
  for_each = local.shared_sg_source_security_group_rules

  security_group_id            = aws_security_group.shared[0].id
  ip_protocol                  = local.restrict_shared_sg_ports ? var.security_group_protocol : "-1"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.source_sg
  description                  = "VPC endpoint access from ${each.value.source_sg}${each.value.port != null ? " on port ${each.value.port}" : ""}"
}
