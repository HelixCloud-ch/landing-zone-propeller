output "id" {
  description = "ID of the Transit Gateway."
  value       = aws_ec2_transit_gateway.this.id
}

output "arn" {
  description = "ARN of the Transit Gateway."
  value       = aws_ec2_transit_gateway.this.arn
}

output "share_arn" {
  description = "ARN of the RAM share. The TGW is already associated with the whole Organization; this output is available for informational purposes or future per-OU scoping."
  value       = aws_ram_resource_share.tgw.arn
}
