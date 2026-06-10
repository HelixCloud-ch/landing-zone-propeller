output "route_table_ids" {
  description = "Map of egress tier name to its route table ID (the same tables that workload-vpc created)."
  value       = { for tier, rt in data.aws_route_table.egress : tier => rt.id }
}

output "attachment_state" {
  description = "State of the TGW VPC attachment at the time this project last applied successfully."
  value       = data.external.attachment_state.result["state"]
}
