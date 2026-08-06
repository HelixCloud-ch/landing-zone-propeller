# ── Service Catalog product identity ─────────────────────────────────────────

variable "product_id" {
  type        = string
  description = "ID of the Service Catalog product (e.g. prod-xxxx)."

  validation {
    condition     = can(regex("^prod-[0-9a-z]+$", var.product_id))
    error_message = "product_id must be a valid Service Catalog product ID (e.g. prod-xxxxxxxxxxxx)."
  }
}

variable "provisioning_artifact_id" {
  type        = string
  description = "ID of the provisioning artifact (product version) to use (e.g. pa-xxxx). Changing this triggers an in-place update of the provisioned product."

  validation {
    condition     = can(regex("^pa-[0-9a-z]+$", var.provisioning_artifact_id))
    error_message = "provisioning_artifact_id must be a valid artifact ID (e.g. pa-xxxxxxxxxxxx)."
  }
}

variable "portfolio_id" {
  type        = string
  description = "ID of the Service Catalog portfolio (e.g. port-xxxx). Used to associate the Terraform execution role with the portfolio before provisioning."

  validation {
    condition     = can(regex("^port-[0-9a-z]+$", var.portfolio_id))
    error_message = "portfolio_id must be a valid Service Catalog portfolio ID (e.g. port-xxxxxxxxxxxx)."
  }
}

variable "terraform_role_arn" {
  type        = string
  description = "ARN of the IAM role Terraform runs as in the target account. Associated with the portfolio so it can call provision-product."
}

variable "provisioned_product_name" {
  type        = string
  description = "Name for the Service Catalog provisioned product."
  default     = "deploy-runner"
}

# ── CloudFormation template parameters ───────────────────────────────────────

variable "cb_project_name" {
  type        = string
  description = "Name of the CodeBuild project (ProjectName parameter)."
  default     = "deploy-runner"
}

variable "create_bucket" {
  type        = bool
  description = "Whether to create the IaC state S3 bucket (state-iac-{account}-{region}-an)."
  default     = true
}

variable "s3_source_bucket" {
  type        = string
  description = "Source S3 bucket in the operations account (S3ReadBuckets parameter). The autopilot injects the actual source at build time; the project itself uses NO_SOURCE."
  default     = ""
}

variable "caller_arn" {
  type        = string
  description = "ARN of the role that assumes deploy-runner-run-role in the target account (CallerARN). Typically propeller-autopilot-role in operations."
  default     = ""
}

variable "caller_account_id" {
  type        = string
  description = "AWS account ID of the caller (CallerAccountId). Required with caller_arn to create the cross-account run role."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the provisioned product and propagated by Service Catalog to the created resources."
  default     = {}
}
