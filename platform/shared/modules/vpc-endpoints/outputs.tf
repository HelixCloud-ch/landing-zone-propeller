output "endpoint_ids" {
  description = "Map of endpoint key to its VPC endpoint ID (Interface and Gateway)."
  value       = { for k, e in aws_vpc_endpoint.this : k => e.id }
}

output "interface_dns_entries" {
  description = "Map of Interface endpoint key to its list of {dns_name, hosted_zone_id} objects. Useful when private_dns_enabled is false and a caller must wire its own Route 53 record. Gateway endpoint keys are omitted."
  value       = { for k, v in var.endpoints : k => aws_vpc_endpoint.this[k].dns_entry if v.type == "Interface" }
}

output "interface_network_interface_ids" {
  description = "Map of Interface endpoint key to its list of network interface IDs, one per Availability Zone. Gateway endpoint keys are omitted."
  value       = { for k, v in var.endpoints : k => aws_vpc_endpoint.this[k].network_interface_ids if v.type == "Interface" }
}

output "gateway_prefix_list_ids" {
  description = "Map of Gateway endpoint key to its prefix list ID. Consumed by downstream projects that need to reference the service's CIDR range in a security group rule instead of 0.0.0.0/0. Interface endpoint keys are omitted."
  value       = { for k, v in var.endpoints : k => aws_vpc_endpoint.this[k].prefix_list_id if v.type == "Gateway" }
}
