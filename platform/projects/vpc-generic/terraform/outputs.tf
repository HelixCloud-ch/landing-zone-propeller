output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  value       = module.vpc.vpc_cidr
}

output "subnet_ids_by_tier" {
  description = "Map of subnet tier name to its ordered list of subnet IDs."
  value       = module.subnets.subnet_ids
}
