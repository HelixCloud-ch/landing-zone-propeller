output "vpc_id" {
  description = "ID of the workload VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the workload VPC. Consumed by network-spokes as the spoke's cidrs registry entry."
  value       = module.vpc.vpc_cidr
}

output "tgw_attachment_id" {
  description = "ID of the TGW VPC attachment. Pass this to the network team to accept it in network-spokes, then run the workload-vpc-routes step."
  value       = module.tgw_attach.attachment_id
}

output "subnet_ids_by_tier" {
  description = "Map of subnet tier name to its ordered list of subnet IDs. Consumed by workload-vpc-routes and downstream workload platforms."
  value       = module.subnets.subnet_ids
}
