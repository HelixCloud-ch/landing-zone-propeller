output "vpc_id" {
  description = "ID of the hub VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the hub VPC."
  value       = aws_vpc.this.cidr_block
}

output "igw_id" {
  description = "ID of the internet gateway attached to the hub VPC, or null when create_internet_gateway is false."
  value       = var.create_internet_gateway ? aws_internet_gateway.this[0].id : null
}
