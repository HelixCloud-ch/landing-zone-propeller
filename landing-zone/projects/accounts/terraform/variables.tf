variable "region" {
  type        = string
  description = "AWS region for the Service Catalog API call (must match the Control Tower home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Accounts ─────────────────────────────────────────────────────────────────

variable "accounts" {
  type = map(object({
    email               = string
    sso_user_email      = optional(string)
    sso_user_first_name = optional(string, "Admin")
    sso_user_last_name  = optional(string, "Account")
  }))
  description = <<-EOT
    Accounts to vend into the Infrastructure OU, keyed by name (also the
    pipeline target name). sso_user_email defaults to email. See README.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for name in keys(var.accounts) : can(regex("^[a-z0-9][a-z0-9-]{0,49}$", name))])
    error_message = "Account names must be lowercase alphanumerics and hyphens, 1-50 characters, starting with a letter or digit."
  }

  validation {
    condition     = length(setintersection(keys(var.accounts), var.reserved_account_names)) == 0
    error_message = "Account names collide with reserved names: ${join(", ", setintersection(keys(var.accounts), var.reserved_account_names))}."
  }
}

# ── OU placement (pipeline-wired) ────────────────────────────────────────────

variable "infrastructure_ou_id" {
  type        = string
  description = "Infrastructure OU ID, from ou-infrastructure."
}

variable "infrastructure_ou_name" {
  type        = string
  description = "Infrastructure OU name, from ou-infrastructure."
}

# ── Internal (framework-managed) ─────────────────────────────────────────────

variable "reserved_account_names" {
  type        = set(string)
  description = "Names reserved by the framework for other accounts; keys of accounts must not use them."
  default     = ["management", "operations", "network", "log-archive", "audit", "backup-admin", "backup-central"]
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
