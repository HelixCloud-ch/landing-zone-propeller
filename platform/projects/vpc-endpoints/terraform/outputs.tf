output "endpoint_ids" {
  description = "Map of endpoint key to its VPC endpoint ID (Interface and Gateway)."
  value       = module.vpc_endpoints.endpoint_ids
}

output "gateway_prefix_list_ids" {
  description = "Map of Gateway endpoint key to its prefix list ID. Consumed by downstream projects that need to reference the service's CIDR range in a security group rule instead of 0.0.0.0/0."
  value       = module.vpc_endpoints.gateway_prefix_list_ids
}

# todo: too big to fit into a propeller output, commented out for now
# output "interface_dns_entries" {
#   description = "Map of Interface endpoint key to its list of {dns_name, hosted_zone_id} objects. Useful when private_dns_enabled is false and a caller must wire its own Route 53 record."
#   value       = module.vpc_endpoints.interface_dns_entries
# }

output "shared_security_group_id" {
  description = "ID of the shared fallback security group created for Interface endpoints that didn't bring their own security_group_ids, or null when every Interface entry supplied its own (or there are no Interface endpoints)."
  value       = local.create_shared_security_group ? aws_security_group.shared[0].id : null
}
