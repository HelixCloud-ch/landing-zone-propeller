output "route_table_ids" {
  description = "Map of tier name to route table ID for all tiers that have subnets."
  value       = module.routes.route_table_ids
}

output "route_keys" {
  description = "Keys of the created routes (\"<tier>-<destination>\"). Needed when writing moved blocks or import commands."
  value       = module.routes.route_keys
}
