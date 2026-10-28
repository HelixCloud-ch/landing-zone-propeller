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

# ── Pipeline inputs (from workload-vpc-endpoints outputs) ─────────────────────

variable "interface_endpoint_id" {
  type        = string
  description = "ID of the S3 interface VPC endpoint used in the aws:SourceVpce condition of the bucket policy. Wire from workload-vpc-endpoints.endpoint_ids using a pipeline input transform that selects the desired key."

  validation {
    condition     = can(regex("^vpce-[0-9a-f]{8,17}$", var.interface_endpoint_id))
    error_message = "interface_endpoint_id must be a valid VPC endpoint ID (e.g. vpce-0123456789abcdef0)."
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
