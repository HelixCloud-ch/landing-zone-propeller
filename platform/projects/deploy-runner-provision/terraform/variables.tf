variable "region" {
  type        = string
  description = "AWS region for the Service Catalog API call (must match the Control Tower home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Target account ─────────────────────────────────────────────────────────────

variable "account_id" {
  type        = string
  description = "Account ID to provision the deploy-runner into. The provider assumes assume_role_name here."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "assume_role_name" {
  type        = string
  description = "IAM role assumed in the target account. AWSControlTowerExecution is present in all CT-enrolled accounts and is used here because the deploy-runner does not yet exist in the target."
  default     = "AWSControlTowerExecution"
}

# ── Service Catalog identity (wired from @landing-zone/shared-outputs) ─────────

variable "portfolio_id" {
  type        = string
  description = "Service Catalog portfolio ID (e.g. port-xxxx)."

  validation {
    condition     = can(regex("^port-[0-9a-z]+$", var.portfolio_id))
    error_message = "portfolio_id must be a valid Service Catalog portfolio ID."
  }
}

variable "product_id" {
  type        = string
  description = "Service Catalog product ID (e.g. prod-xxxx)."

  validation {
    condition     = can(regex("^prod-[0-9a-z]+$", var.product_id))
    error_message = "product_id must be a valid Service Catalog product ID."
  }
}

variable "provisioning_artifact_id" {
  type        = string
  description = "Service Catalog provisioning artifact (version) ID (e.g. pa-xxxx)."

  validation {
    condition     = can(regex("^pa-[0-9a-z]+$", var.provisioning_artifact_id))
    error_message = "provisioning_artifact_id must be a valid artifact ID."
  }
}

variable "provisioned_product_name" {
  type        = string
  description = "Name for the provisioned product in the target account."
  default     = "deploy-runner"
}

# ── CloudFormation parameters ─────────────────────────────────────────────────

variable "cb_project_name" {
  type        = string
  description = "Name of the CodeBuild project (ProjectName parameter)."
  default     = "deploy-runner"
}

variable "create_bucket" {
  type        = bool
  description = "Whether to create the IaC state S3 bucket. Set to false if it already exists."
  default     = true
}

variable "s3_source_bucket" {
  type        = string
  description = "Source S3 bucket in the operations account (S3ReadBuckets parameter)."
  default     = ""
}

variable "caller_arn" {
  type        = string
  description = "ARN of the autopilot role that assumes deploy-runner-run-role in the target (CallerARN)."
  default     = ""
}

variable "caller_account_id" {
  type        = string
  description = "Operations account ID (CallerAccountId)."
  default     = ""
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type        = map(string)
  description = "Per-project tags applied via provider default_tags."
  default     = {}
}

variable "consumer_tags" {
  type        = map(string)
  description = "Pipeline-wide tags applied via provider default_tags."
  default     = {}
}

variable "propeller_tags" {
  type        = map(string)
  description = "Framework-managed tags applied via provider default_tags."
  default     = {}
}
