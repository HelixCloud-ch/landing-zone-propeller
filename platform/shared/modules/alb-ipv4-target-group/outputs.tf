output "arn" {
  description = "Target group ARN."
  value       = aws_lb_target_group.this.arn
}

output "arn_suffix" {
  description = "ARN suffix for CloudWatch metrics."
  value       = aws_lb_target_group.this.arn_suffix
}

output "name" {
  description = "Target group name."
  value       = aws_lb_target_group.this.name
}

output "target_ips" {
  description = "IPs attached to the target group."
  value       = sort(keys(aws_lb_target_group_attachment.this))
}
