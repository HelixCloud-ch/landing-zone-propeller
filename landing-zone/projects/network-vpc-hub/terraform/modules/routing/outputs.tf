output "route_table_ids" {
  description = "Map of subnet tier name to its route table ID. Only tiers that have subnets appear."
  value       = { for tier, rt in aws_route_table.this : tier => rt.id }
}
