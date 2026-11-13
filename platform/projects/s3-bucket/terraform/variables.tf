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

variable "enforce_kms_key" {
  type        = bool
  description = <<-EOT
    Deny uploads that request another encryption or KMS key (default policy only).
    Ignored when kms_key_arn is null, or when no default policy is applied.
  EOT
  default     = false

  validation {
    condition = (
      !var.enforce_kms_key || var.kms_key_arn == null ||
      can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    )
    error_message = "With enforce_kms_key, kms_key_arn must be a key ARN (arn:...:key/<id>), not an alias or a key ID."
  }
}

# ── Bucket policy ─────────────────────────────────────────────────────────────

variable "manage_bucket_policy" {
  type        = bool
  description = <<-EOT
    Create the bucket policy. Set false to manage it outside this project
    (one policy per bucket). Then bucket_policy_json must stay null.
  EOT
  default     = true
}

variable "bucket_policy_json" {
  type        = string
  description = "Bucket policy as a JSON string. When null, a built-in DenyInsecureTransport (TLS-only) policy is applied. Pass an alternative policy to override; build it with aws_iam_policy_document in the overlay or the consumer pipeline and pass the .json result here."
  default     = null

  validation {
    condition     = var.bucket_policy_json == null || var.manage_bucket_policy
    error_message = "bucket_policy_json cannot be set when manage_bucket_policy is false."
  }
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
