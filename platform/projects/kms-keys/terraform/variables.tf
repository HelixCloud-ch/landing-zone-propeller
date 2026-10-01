variable "region" {
  type        = string
  description = "AWS region of the keys."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Pipeline inputs ──────────────────────────────────────────────────────────

variable "workload_account_ids" {
  type        = map(string)
  description = "Account name to ID, from @landing-zone/workload-parameters.account_ids. Resolves shared_with."
  default     = {}
}

variable "landing_zone_account_ids" {
  type        = map(string)
  description = "Account name to ID, from @landing-zone/accounts.account_ids. Resolves shared_with."
  default     = {}

  validation {
    condition = length(setintersection(
      [for n in keys(var.workload_account_ids) : lower(replace(n, " ", "-"))],
      [for n in keys(var.landing_zone_account_ids) : lower(replace(n, " ", "-"))],
    )) == 0
    error_message = "An account name appears in both workload_account_ids and landing_zone_account_ids."
  }
}

variable "organization_id" {
  type        = string
  description = "Organization ID, from @landing-zone/workload-parameters.organization_id. Needed for share_with_organization."
  default     = null
}

# ── Keys ─────────────────────────────────────────────────────────────────────

variable "keys" {
  type = map(object({
    description             = optional(string)
    alias                   = optional(string)
    shared_with             = optional(list(string), [])
    account_ids             = optional(list(string), [])
    share_with_organization = optional(bool, false)
    org_paths               = optional(list(string), [])
    enable_rotation         = optional(bool, true)
    rotation_period_in_days = optional(number)
    deletion_window_in_days = optional(number, 30)
  }))
  description = <<-EOT
    Keys to create, keyed by name (output map key). alias defaults to
    propeller/<name>; shared_with lists account names (target names) from the
    landing-zone maps. See README for the field reference.
  EOT

  validation {
    condition = alltrue(flatten([
      for k in values(var.keys) : [
        for n in k.shared_with : contains(concat(
          [for a in keys(var.workload_account_ids) : lower(replace(a, " ", "-"))],
          [for a in keys(var.landing_zone_account_ids) : lower(replace(a, " ", "-"))],
        ), n)
      ]
    ]))
    error_message = "Every shared_with entry must be an account name from workload_account_ids or landing_zone_account_ids (lowercase, spaces as hyphens)."
  }

  validation {
    condition     = length(distinct([for name, k in var.keys : coalesce(k.alias, "propeller/${name}")])) == length(var.keys)
    error_message = "Two keys resolve to the same alias."
  }

  validation {
    condition     = alltrue([for k in values(var.keys) : !k.share_with_organization || var.organization_id != null])
    error_message = "share_with_organization requires organization_id."
  }

  validation {
    condition     = alltrue([for k in values(var.keys) : length(k.org_paths) == 0 || k.share_with_organization])
    error_message = "org_paths requires share_with_organization = true."
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
