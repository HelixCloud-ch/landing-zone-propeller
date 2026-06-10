locals {
  # Stable per-tier view, ordered by az_index, for every tier key declared in
  # var.tiers (disabled tiers yield an empty list so downstream consumers get a
  # predictable shape).
  subnets_by_tier_full = {
    for tier_name in keys(var.tiers) : tier_name => [
      for inst_key in sort([
        for k, v in local.subnet_instances : k if v.tier == tier_name
        ]) : {
        id   = aws_subnet.this[inst_key].id
        az   = local.subnet_instances[inst_key].az
        cidr = local.subnet_instances[inst_key].cidr
      }
    ]
  }
}

output "subnet_ids" {
  description = "Map of subnet tier name to the ordered list of subnet IDs. Disabled or empty tiers map to an empty list."
  value       = { for tier_name, subnets in local.subnets_by_tier_full : tier_name => [for s in subnets : s.id] }
}

output "subnets_by_tier" {
  description = "Map of subnet tier name to an ordered list of subnet objects ({ id, az, cidr }), consumed by the routing and tgw-attach modules."
  value       = local.subnets_by_tier_full
}
