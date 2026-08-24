output "attachment_id" {
  description = "ID of the TGW VPC attachment. Lands in pendingAcceptance until network-spokes accepts it in the network account."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}

output "attachment_arn" {
  description = "ARN of the TGW VPC attachment."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.arn
}
