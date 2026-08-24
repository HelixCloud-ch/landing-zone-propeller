# ── Correlation: typed tier_routes -> module input ───────────────────────────
# Each route entry sets exactly one typed field. The project resolves it to a
# concrete ID via a straight map lookup — no prefix parsing, no dispatch table.

locals {
  # ID prefix -> aws_route argument. Only used for route_targets (escape hatch).
  argument_by_prefix = {
    igw  = "gateway_id"
    vgw  = "gateway_id"
    nat  = "nat_gateway_id"
    tgw  = "transit_gateway_id"
    pcx  = "vpc_peering_connection_id"
    vpce = "vpc_endpoint_id"
    eigw = "egress_only_gateway_id"
    eni  = "network_interface_id"
    cagw = "carrier_gateway_id"
    lgw  = "local_gateway_id"
  }

  active_tiers = {
    for tier, ids in var.subnet_ids_by_tier : tier => ids if length(ids) > 0
  }

  route_tables = {
    for tier in keys(local.active_tiers) : tier => {
      name = "${var.name_prefix}-${tier}-rt"
    }
  }

  associations = merge([
    for tier, ids in local.active_tiers : {
      for idx, id in ids : "${tier}-${idx}" => {
        route_table_key = tier
        subnet_id       = id
      }
    }
  ]...)

  # Resolve each typed route to a concrete ID and the aws_route argument.
  resolved = merge([
    for tier, routes in var.tier_routes : {
      for r in routes : "${tier}-${r.destination}" => merge(
        { route_table_key = tier, destination_cidr_block = r.destination },
        r.igw == true ? { id = var.igw_id, argument = "gateway_id" } :
        r.vgw == true ? { id = var.vgw_id, argument = "gateway_id" } :
        r.tgw_key != null ? { id = lookup(var.tgw_ids, r.tgw_key, null), argument = "transit_gateway_id" } :
        r.natgw_key != null ? { id = lookup(var.natgw_ids, r.natgw_key, null), argument = "nat_gateway_id" } :
        r.peering_key != null ? { id = lookup(var.peering_ids, r.peering_key, null), argument = "vpc_peering_connection_id" } :
        r.vpce_key != null ? { id = lookup(var.vpc_endpoint_ids, r.vpce_key, null), argument = "vpc_endpoint_id" } :
        r.target_key != null ? {
          id = lookup(var.route_targets, r.target_key, null),
          argument = lookup(
            local.argument_by_prefix,
            split("-", lookup(var.route_targets, r.target_key, ""))[0],
            startswith(lookup(var.route_targets, r.target_key, ""), "arn:") ? "core_network_arn" : null
          )
        } :
        { id = null, argument = null }
      )
    } if contains(keys(local.active_tiers), tier)
  ]...)

  unresolved_targets = [
    for k, r in local.resolved : k if r.id == null
  ]

  unroutable_targets = [
    for k, r in local.resolved : k if r.id != null && r.argument == null
  ]

  # Project resolved data onto the module's explicit-argument shape.
  routes = {
    for k, r in local.resolved : k => {
      route_table_key        = r.route_table_key
      destination_cidr_block = r.destination_cidr_block

      carrier_gateway_id        = r.argument == "carrier_gateway_id" ? r.id : null
      core_network_arn          = r.argument == "core_network_arn" ? r.id : null
      egress_only_gateway_id    = r.argument == "egress_only_gateway_id" ? r.id : null
      gateway_id                = r.argument == "gateway_id" ? r.id : null
      local_gateway_id          = r.argument == "local_gateway_id" ? r.id : null
      nat_gateway_id            = r.argument == "nat_gateway_id" ? r.id : null
      network_interface_id      = r.argument == "network_interface_id" ? r.id : null
      transit_gateway_id        = r.argument == "transit_gateway_id" ? r.id : null
      vpc_endpoint_id           = r.argument == "vpc_endpoint_id" ? r.id : null
      vpc_peering_connection_id = r.argument == "vpc_peering_connection_id" ? r.id : null
    }
  }
}

resource "terraform_data" "targets_resolved" {
  input = length(local.resolved)

  lifecycle {
    precondition {
      condition     = length(local.unresolved_targets) == 0
      error_message = "Routes reference undefined target keys: ${join(", ", local.unresolved_targets)}. Check that the corresponding ID variable contains the referenced key."
    }

    precondition {
      condition     = length(local.unroutable_targets) == 0
      error_message = "Routes via target_key reference IDs whose prefix is not routable: ${join(", ", local.unroutable_targets)}. Supported prefixes: ${jsonencode(sort(keys(local.argument_by_prefix)))}, or a Cloud WAN core network ARN."
    }
  }
}

module "routes" {
  source = "../../../shared/modules/vpc-routes"

  vpc_id       = var.vpc_id
  route_tables = local.route_tables
  associations = local.associations
  routes       = local.routes

  depends_on = [
    terraform_data.targets_resolved,
  ]
}
