output "vpc_id" {
  description = "ID of the workload VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the workload VPC."
  value       = aws_vpc.this.cidr_block
}
