output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "ID of the S3 bucket (same as bucket name; exposed separately for use in depends_on)."
  value       = aws_s3_bucket.this.id
}
