variable "region" {
  type        = string
  description = "AWS region for Control Tower operations (must match landing zone home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "ou_name" {
  type        = string
  description = "Name of the Infrastructure OU."
  default     = "Infrastructure"
}

variable "baseline_version" {
  type        = string
  description = "Initial version of AWSControlTowerBaseline to enable. Ignored after first apply (lifecycle ignore_changes). See https://docs.aws.amazon.com/controltower/latest/userguide/table-of-baselines.html"
  default     = "5.0"
}

variable "operations_account_id" {
  type        = string
  description = "Account ID of the operations account to move into this OU."

  validation {
    condition     = can(regex("^\\d{12}$", var.operations_account_id))
    error_message = "operations_account_id must be a 12-digit AWS account ID."
  }
}

# ── Tags ─────────────────────────────────────────────────────────────────────

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
