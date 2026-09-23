output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = module.bucket.bucket_name
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = module.bucket.bucket_arn
}

output "bucket_id" {
  description = "ID of the S3 bucket."
  value       = module.bucket.bucket_id
}

output "tg_static_arn" {
  description = "ARN of the ALB target group backing this bucket."
  value       = aws_lb_target_group.static.arn
}

output "bucket_hostname" {
  description = "FQDN of the bucket for virtual-hosted-style S3 access (<bucket>.s3.<region>.amazonaws.com)."
  value       = "${module.bucket.bucket_name}.s3.${data.aws_region.current.region}.amazonaws.com"
}
