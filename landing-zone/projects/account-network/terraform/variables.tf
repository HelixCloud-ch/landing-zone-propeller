variable "region" {
  type        = string
  description = "AWS region for the Service Catalog API call (must match the Control Tower home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Account identity ─────────────────────────────────────────────────────────

variable "account_name" {
  type        = string
  description = "Friendly name for the Network account."
  default     = "Network"
}

variable "account_email" {
  type        = string
  description = "Root email address for the Network account."
  sensitive   = true
}

# ── OU placement ─────────────────────────────────────────────────────────────

variable "ou_name" {
  type        = string
  description = "Name of the OU where the Network account will be placed (typically the Infrastructure OU)."
}

variable "ou_id" {
  type        = string
  description = "ID of the target OU. Wired from ou-infrastructure outputs via the propeller pipeline."
}

variable "sso_user_email" {
  type        = string
  description = "Email for the SSO user that Account Factory creates. Defaults to account_email when empty."
  sensitive   = true
  default     = ""
}

variable "sso_user_first_name" {
  type        = string
  description = "First name for the Account Factory SSO user."
  default     = "Network"
}

variable "sso_user_last_name" {
  type        = string
  description = "Last name for the Account Factory SSO user."
  default     = "Account"
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
