variable "bucket_prefix" {
  type        = string
  description = "Prefix of the source bucket (e.g. source)."
}

variable "region" {
  type        = string
  description = "AWS region for the bucket."
}

variable "organization_id" {
  type        = string
  description = "AWS Organizations ID for org-wide read access."
}
