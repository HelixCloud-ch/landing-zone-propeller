output "ou_id" {
  description = "ID of the Infrastructure OU."
  value       = aws_organizations_organizational_unit.this.id
}

output "ou_arn" {
  description = "ARN of the Infrastructure OU."
  value       = aws_organizations_organizational_unit.this.arn
}

output "enabled_baseline_arn" {
  description = "ARN of the enabled AWSControlTowerBaseline on this OU."
  value       = aws_controltower_baseline.this.arn
}

output "baseline_version" {
  description = "Version of AWSControlTowerBaseline that was enabled."
  value       = var.baseline_version
}
