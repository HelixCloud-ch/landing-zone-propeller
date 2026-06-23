output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = module.bucket.bucket_name
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = module.bucket.bucket_arn
}

output "bucket_id" {
  description = "ID of the S3 bucket (same as bucket name; exposed separately for use in depends_on and policy attachments)."
  value       = module.bucket.bucket_id
}
