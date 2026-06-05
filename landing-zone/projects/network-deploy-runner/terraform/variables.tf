variable "region" {
  type        = string
  description = "AWS region for the Service Catalog API call (must match the landing zone home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Target account ────────────────────────────────────────────────────────────

variable "network_account_id" {
  type        = string
  description = "AWS account ID of the Network account. Wired from account-network outputs via the propeller pipeline."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.network_account_id))
    error_message = "network_account_id must be a 12-digit AWS account ID."
  }
}

variable "assume_role_name" {
  type        = string
  description = "IAM role to assume in the Network account. AWSControlTowerExecution is present in all CT-enrolled accounts and is used here because the deploy-runner does not yet exist in the Network account."
  default     = "AWSControlTowerExecution"
}

# ── Service Catalog identity (all wired from bootstrap-parameters) ────────────

variable "portfolio_id" {
  type        = string
  description = "ID of the Service Catalog portfolio (e.g. port-xxxx). Wired from bootstrap-parameters outputs via the propeller pipeline. Used for the principal association."

  validation {
    condition     = can(regex("^port-[0-9a-z]+$", var.portfolio_id))
    error_message = "portfolio_id must be a valid Service Catalog portfolio ID (e.g. port-xxxxxxxxxxxx)."
  }
}

variable "product_id" {
  type        = string
  description = "ID of the Service Catalog product (e.g. prod-xxxx). Wired from bootstrap-parameters outputs via the propeller pipeline."

  validation {
    condition     = can(regex("^prod-[0-9a-z]+$", var.product_id))
    error_message = "product_id must be a valid Service Catalog product ID (e.g. prod-xxxxxxxxxxxx)."
  }
}

variable "provisioning_artifact_id" {
  type        = string
  description = "ID of the provisioning artifact (product version) to deploy (e.g. pa-xxxx). Wired from bootstrap-parameters, which resolves the latest active DEFAULT artifact. Changing this value triggers an in-place update of the provisioned product."

  validation {
    condition     = can(regex("^pa-[0-9a-z]+$", var.provisioning_artifact_id))
    error_message = "provisioning_artifact_id must be a valid artifact ID (e.g. pa-xxxxxxxxxxxx)."
  }
}

variable "provisioned_product_name" {
  type        = string
  description = "Name for the provisioned product in the Network account. Defaults to the name used in all other accounts."
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
  description = "Name of the source S3 bucket in the operations account. Passed as the S3ReadBuckets parameter (read access for the deploy bundle, not a fixed CodeBuild source). Wired from bootstrap-parameters outputs via the propeller pipeline."
  default     = ""
}

variable "caller_arn" {
  type        = string
  description = "ARN of the autopilot role that will assume deploy-runner-run-role in the Network account (CallerARN parameter). Wired from bootstrap-parameters outputs via the propeller pipeline."
  default     = ""
}

variable "caller_account_id" {
  type        = string
  description = "AWS account ID of the operations account (CallerAccountId parameter). Wired from SSM /accounts.operations.id via the propeller pipeline."
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
