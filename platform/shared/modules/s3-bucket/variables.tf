# ── Identity ──────────────────────────────────────────────────────────────────

variable "name" {
  type        = string
  description = "Base bucket name. When bucket_namespace is null, used verbatim. When bucket_namespace is \"account-regional\", suffixed with -<account_id>-<region>-an to enforce the account-regional naming convention."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be a valid S3 bucket name fragment (lowercase, alphanumerics, dots and hyphens; 3–63 chars)."
  }
}

variable "bucket_namespace" {
  type        = string
  description = "S3 bucket namespace mode. Set to \"account-regional\" to use the account-regional bucket namespace (and to format the bucket name as <name>-<account_id>-<region>-an). Set to null for the default global S3 namespace."
  default     = null

  validation {
    condition     = var.bucket_namespace == null || var.bucket_namespace == "account-regional"
    error_message = "bucket_namespace must be null or \"account-regional\"."
  }
}

variable "account_id" {
  type        = string
  description = "AWS account ID. Required when bucket_namespace == \"account-regional\"; the caller passes data.aws_caller_identity.current.account_id from its own context."
  default     = null
}

variable "region" {
  type        = string
  description = "AWS region. Required when bucket_namespace == \"account-regional\"; the caller passes its provider region."
  default     = null
}

# ── Versioning ────────────────────────────────────────────────────────────────

variable "versioning_enabled" {
  type        = bool
  description = "Enable S3 object versioning."
  default     = false
}

# ── Encryption ────────────────────────────────────────────────────────────────

variable "kms_key_arn" {
  type        = string
  description = "ARN of a customer-managed KMS key for SSE. When null, AES256 (SSE-S3) is used."
  default     = null
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

variable "force_destroy" {
  type        = bool
  description = "Allow Terraform to delete the bucket even when it contains objects. Test environments only."
  default     = false
}

# ── Public access block ───────────────────────────────────────────────────────
# All four flags are exposed individually. Defaults match the AWS-recommended
# baseline (everything blocked); set to false only with explicit justification.

variable "block_public_acls" {
  type        = bool
  description = "Reject calls to PUT bucket ACLs that grant public access."
  default     = true
}

variable "block_public_policy" {
  type        = bool
  description = "Reject calls to PUT bucket policies that grant public access."
  default     = true
}

variable "ignore_public_acls" {
  type        = bool
  description = "Ignore any public access ACLs already on the bucket or its objects."
  default     = true
}

variable "restrict_public_buckets" {
  type        = bool
  description = "Restrict cross-account access to the bucket when its policy allows public access."
  default     = true
}

# ── Bucket policy ─────────────────────────────────────────────────────────────

variable "bucket_policy_json" {
  type        = string
  description = "Full bucket policy as a JSON string. The caller composes the policy (e.g. DenyInsecureTransport plus grant statements) with aws_iam_policy_document and passes the .json result here. When null, no bucket policy is attached."
  default     = null
}
