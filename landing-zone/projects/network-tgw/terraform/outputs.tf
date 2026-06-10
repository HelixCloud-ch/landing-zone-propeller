output "id" {
  description = "ID of the Transit Gateway."
  value       = aws_ec2_transit_gateway.this.id
}

output "arn" {
  description = "ARN of the Transit Gateway."
  value       = aws_ec2_transit_gateway.this.arn
}

output "share_arn" {
  description = "ARN of the RAM share. Downstream projects use this to add aws_ram_principal_association resources when onboarding workload OUs."
  value       = aws_ram_resource_share.tgw.arn
}
