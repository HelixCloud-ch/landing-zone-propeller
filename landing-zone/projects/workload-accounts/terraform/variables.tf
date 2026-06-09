variable "region" {
  type        = string
  description = "AWS region (must match the Control Tower home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "accounts" {
  type = map(object({
    email               = string
    ou                  = string
    sso_user_email      = optional(string)
    sso_user_first_name = optional(string, "Workload")
    sso_user_last_name  = optional(string, "Account")
  }))
  description = <<-EOT
    Map of workload accounts to create, keyed by account name. The `ou` field
    references an OU path from workload-ous.

    SSO user fields default to the account email for `sso_user_email`, and
    "Workload" / "Account" for first/last name. Override per-account if needed.

    Example:
      accounts = {
        acme-prod = { email = "aws+acme-prod@example.com", ou = "Workloads/Prod" }
        acme-test = { email = "aws+acme-test@example.com", ou = "Workloads/Test" }
      }
  EOT
}

variable "ou_ids" {
  type        = map(string)
  description = "Map of OU path to OU ID, wired from workload-ous outputs."
}

# ── Internal (framework-managed) ──────────────────────────────────────────────

variable "reserved_account_names" {
  type        = set(string)
  description = "Names reserved by the framework for governance accounts. Workload account names must not collide with these."
  default     = ["management", "operations", "network", "log-archive", "audit", "backup-admin", "backup-central"]
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
