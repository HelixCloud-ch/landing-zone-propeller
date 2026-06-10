output "route_table_ids" {
  description = "Map of tier name to route table ID for all tiers that have subnets."
  value       = { for tier, rt in aws_route_table.this : tier => rt.id }
}

output "attachment_state" {
  description = "State of the TGW VPC attachment at the time this project last applied successfully."
  value       = data.external.attachment_state.result["state"]
}
