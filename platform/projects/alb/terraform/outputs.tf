output "alb_arn" {
  description = "Load balancer ARN."
  value       = module.alb.arn
}

output "alb_arn_suffix" {
  description = "Load balancer ARN suffix for CloudWatch metrics."
  value       = module.alb.arn_suffix
}

output "alb_dns_name" {
  description = "Load balancer DNS name."
  value       = module.alb.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the load balancer."
  value       = module.alb.zone_id
}

output "alb_alias" {
  description = "Alias object for a dns-record entry."
  value       = { name = module.alb.dns_name, zone_id = module.alb.zone_id }
}

output "security_group_ids" {
  description = "Attached security group IDs. The created group comes first."
  value       = local.security_group_ids
}

output "target_group_arns" {
  description = "Target group ARNs by key."
  value       = { for k, m in module.target_group : k => m.arn }
}

output "target_group_arn_suffixes" {
  description = "Target group ARN suffixes by key."
  value       = { for k, m in module.target_group : k => m.arn_suffix }
}

output "target_group_names" {
  description = "Target group names by key."
  value       = { for k, m in module.target_group : k => m.name }
}

output "target_ips" {
  description = "Attached target IPs by target group key."
  value       = { for k, m in module.target_group : k => m.target_ips }
}

output "listener_arns" {
  description = "Listener ARNs by key."
  value       = { for k, m in module.listener : k => m.arn }
}

output "listener_rule_arns" {
  description = "Listener rule ARNs by key."
  value       = { for k, m in module.listener_rule : k => m.arn }
}
