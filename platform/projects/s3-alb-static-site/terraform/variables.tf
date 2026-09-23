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
  description = "Base name used for the bucket and the target group. The bucket is suffixed with -<account_id>-<region>-an by the shared s3-bucket module. The target group is suffixed with -tg."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,28}$", var.name))
    error_message = "name must be lowercase, start with a letter, contain only alphanumerics and hyphens, max 29 chars (target group name limit)."
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

# ── Pipeline inputs (from workload-vpc / workload-vpc-endpoints outputs) ──────

variable "vpc_id" {
  type        = string
  description = "ID of the workload VPC. Sourced from the workload-vpc project output."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (e.g. vpc-0123456789abcdef0)."
  }
}

variable "interface_endpoint_id" {
  type        = string
  description = "ID of the S3 interface VPC endpoint used in the aws:SourceVpce condition of the bucket policy. Wire from workload-vpc-endpoints.endpoint_ids using a pipeline input transform that selects the desired key."

  validation {
    condition     = can(regex("^vpce-[0-9a-f]{8,17}$", var.interface_endpoint_id))
    error_message = "interface_endpoint_id must be a valid VPC endpoint ID (e.g. vpce-0123456789abcdef0)."
  }
}

variable "interface_eni_ids" {
  type        = list(string)
  description = "ENI IDs of the S3 interface VPC endpoint. Resolved to private IPs and registered as ALB targets. Wire from workload-vpc-endpoints.interface_network_interface_ids using a pipeline input transform that selects the desired key."

  validation {
    condition     = length(var.interface_eni_ids) > 0 && alltrue([for eni in var.interface_eni_ids : can(regex("^eni-[0-9a-f]{8,17}$", eni))])
    error_message = "interface_eni_ids must be a non-empty list of valid ENI IDs (e.g. eni-0123456789abcdef0)."
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
