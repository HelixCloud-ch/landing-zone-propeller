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

output "bucket_hostname" {
  description = "FQDN of the bucket for virtual-hosted-style S3 access (<bucket>.s3.<region>.amazonaws.com). Consumed by Ingress host-header-rewrite transforms so requests reach S3 as the correct virtual-hosted bucket."
  value       = "${module.bucket.bucket_name}.s3.${data.aws_region.current.region}.amazonaws.com"
}
