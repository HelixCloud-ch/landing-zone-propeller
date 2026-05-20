output "landing_zone_arn" {
  description = "ARN of the Control Tower landing zone."
  value       = aws_controltower_landing_zone.this.arn
}

output "landing_zone_id" {
  description = "Identifier of the Control Tower landing zone."
  value       = aws_controltower_landing_zone.this.id
}

output "drift_status" {
  description = "Drift status of the landing zone."
  value       = aws_controltower_landing_zone.this.drift_status
}

output "latest_available_version" {
  description = "Latest available landing zone version."
  value       = aws_controltower_landing_zone.this.latest_available_version
}
