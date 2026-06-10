output "vpc_id" {
  description = "ID of the hub VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the hub VPC."
  value       = module.vpc.vpc_cidr
}

output "regional_nat_gateway_id" {
  description = "ID of the regional NAT gateway."
  value       = module.nat.regional_nat_gateway_id
}

output "regional_nat_route_table_id" {
  description = "ID of the route table automatically created by the regional NAT gateway. Consumed by network-spokes to write spoke-CIDR -> TGW return routes so the NAT can route reply packets back to spoke VPCs."
  value       = module.nat.route_table_id
}

# Per-tier subnet ID lists. Tiers that are disabled or absent yield an empty
# list so downstream consumers get a stable shape.
output "public_subnet_ids" {
  description = "IDs of the public tier subnets (empty when the tier is disabled)."
  value       = lookup(module.subnets.subnet_ids, "public", [])
}

output "private_subnet_ids" {
  description = "IDs of the private tier subnets (empty when the tier is disabled)."
  value       = lookup(module.subnets.subnet_ids, "private", [])
}

output "tgw_subnet_ids" {
  description = "IDs of the tgw tier subnets, reserved for the future network-vpc-hub-attach project (empty when the tier is disabled)."
  value       = lookup(module.subnets.subnet_ids, "tgw", [])
}

output "resolver_subnet_ids" {
  description = "IDs of the resolver tier subnets, consumed by the future network-resolver project (empty when the tier is disabled)."
  value       = lookup(module.subnets.subnet_ids, "resolver", [])
}

output "subnet_ids_by_tier" {
  description = "Map of subnet tier name to its ordered list of subnet IDs."
  value       = module.subnets.subnet_ids
}

output "route_table_ids" {
  description = "Map of subnet tier name to its route table ID (only tiers that have subnets appear)."
  value       = module.routing.route_table_ids
}
