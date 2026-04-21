variable "bucket_name" {
  type        = string
  description = "Name of the source bucket (e.g. source-{account_id}-{region})."
}

variable "region" {
  type        = string
  description = "AWS region for the bucket."
}

variable "organization_id" {
  type        = string
  description = "AWS Organizations ID for org-wide read access."
}
