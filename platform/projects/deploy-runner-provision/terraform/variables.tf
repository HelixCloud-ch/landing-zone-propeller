variable "region" {
  type        = string
  description = "AWS region (must match the Control Tower home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Target account ─────────────────────────────────────────────────────────────

variable "account_id" {
  type        = string
  description = "Workload account ID to provision the deploy-runner into."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "account_name" {
  type        = string
  description = "Human-readable name for the target account (logging only)."
  default     = ""
}

variable "assume_role_name" {
  type        = string
  description = "IAM role assumed in the target account for provisioning. Trusted by the management account (Control Tower)."
  default     = "AWSControlTowerExecution"
}

# ── Service Catalog identity ──────────────────────────────────────────────────

variable "portfolio_id" {
  type        = string
  description = "Service Catalog portfolio ID."

  validation {
    condition     = can(regex("^port-[0-9a-z]+$", var.portfolio_id))
    error_message = "portfolio_id must be a valid Service Catalog portfolio ID."
  }
}

variable "product_id" {
  type        = string
  description = "Service Catalog product ID."

  validation {
    condition     = can(regex("^prod-[0-9a-z]+$", var.product_id))
    error_message = "product_id must be a valid Service Catalog product ID."
  }
}

variable "provisioning_artifact_id" {
  type        = string
  description = "Service Catalog provisioning artifact (version) ID."

  validation {
    condition     = can(regex("^pa-[0-9a-z]+$", var.provisioning_artifact_id))
    error_message = "provisioning_artifact_id must be a valid artifact ID."
  }
}

# ── CloudFormation parameters ─────────────────────────────────────────────────

variable "s3_source_bucket" {
  type        = string
  description = "Source S3 bucket in the operations account (bundle)."
  default     = ""
}

variable "caller_arn" {
  type        = string
  description = "ARN of the autopilot role (trusted to assume the run-role)."
  default     = ""
}

variable "caller_account_id" {
  type        = string
  description = "Operations account ID."
  default     = ""
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Per-project tags applied to all resources via provider default_tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags applied to all resources via provider default_tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags applied to all resources via provider default_tags."
  default     = {}
}
