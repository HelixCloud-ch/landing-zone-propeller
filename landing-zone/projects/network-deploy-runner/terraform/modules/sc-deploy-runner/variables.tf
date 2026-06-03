# ── Service Catalog product identity ─────────────────────────────────────────

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
  description = "ID of the provisioning artifact (product version) to use (e.g. pa-xxxx). Wired from bootstrap-parameters, which resolves the latest active DEFAULT artifact at pipeline run time. Changing this value triggers an in-place update of the provisioned product."

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
  description = "ARN of the IAM role that Terraform is running as in the target account. Associated with the portfolio so it can call provision-product."
}

variable "provisioned_product_name" {
  type        = string
  description = "Name for the Service Catalog provisioned product. Defaults to the name used by bootstrap across all accounts."
  default     = "deploy-runner"
}

# ── CloudFormation template parameters ───────────────────────────────────────

variable "cb_project_name" {
  type        = string
  description = "Name of the CodeBuild project (ProjectName parameter in the deploy-runner CloudFormation template)."
  default     = "deploy-runner"
}

variable "create_bucket" {
  type        = bool
  description = "Whether to create the IaC state S3 bucket (state-iac-{account}-{region}-an). Set to false if it already exists."
  default     = true
}

variable "s3_source_bucket" {
  type        = string
  description = "Name of the source S3 bucket in the operations account (CBS3SourceBucket parameter). Grants the CodeBuild role read access to the deploy bundle."
  default     = ""
}

variable "caller_arn" {
  type        = string
  description = "ARN of the IAM role that will assume deploy-runner-run-role in the target account (CallerARN parameter). Typically propeller-autopilot-role in the operations account."
  default     = ""
}

variable "caller_account_id" {
  type        = string
  description = "AWS account ID of the caller (CallerAccountId parameter). Required together with caller_arn to create the cross-account run role."
  default     = ""
}
