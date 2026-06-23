variable "region" {
  type        = string
  description = "AWS region."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Identity ──────────────────────────────────────────────────────────────────

variable "name" {
  type        = string
  description = "Base bucket name. The full bucket name is suffixed with -<account_id>-<region>-an by the shared s3-bucket module to enforce account-regional naming."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.name))
    error_message = "name must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 31 chars."
  }
}

# ── Bucket options ────────────────────────────────────────────────────────────

variable "versioning_enabled" {
  type        = bool
  description = "Enable S3 object versioning."
  default     = false
}

variable "force_destroy" {
  type        = bool
  description = "Allow Terraform to delete the bucket even when non-empty. Test environments only."
  default     = false
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of a customer-managed KMS key for SSE. When null, AES256 (SSE-S3) is used."
  default     = null
}

# ── Bucket policy ─────────────────────────────────────────────────────────────

variable "bucket_policy_json" {
  type        = string
  description = "Bucket policy as a JSON string. When null, a built-in DenyInsecureTransport (TLS-only) policy is applied. Pass an alternative policy to override; build it with aws_iam_policy_document in the overlay or the consumer pipeline and pass the .json result here."
  default     = null
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Per-project tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags."
  default     = {}
}
