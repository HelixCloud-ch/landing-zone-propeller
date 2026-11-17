output "arn" {
  description = "Load balancer ARN."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "ARN suffix for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "Load balancer DNS name."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Hosted zone ID of the load balancer, for alias records."
  value       = aws_lb.this.zone_id
}
