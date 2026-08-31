output "route_table_ids" {
  description = "Map of route table key to route table ID."
  value       = { for k, rt in aws_route_table.this : k => rt.id }
}

output "route_keys" {
  description = "Keys of the created routes. Needed when writing moved blocks or import commands."
  value       = sort(keys(aws_route.this))
}
