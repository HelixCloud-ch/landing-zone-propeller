output "segment_route_table_ids" {
  description = "Map of segment name to TGW route table ID owned by this project."
  value       = { for k, rt in aws_ec2_transit_gateway_route_table.segment : k => rt.id }
}

output "accepted_attachments" {
  description = "Map of friendly name to {attachment_id, cidrs, segment} for each accepted spoke. Consumed by network-routing to write hub->spoke return routes into the main table; network-spokes never writes into main."
  value = {
    for k, s in local.spokes : k => {
      attachment_id = aws_ec2_transit_gateway_vpc_attachment_accepter.spoke[k].id
      cidrs         = s.cidrs
      segment       = s.segment
    }
  }
}
