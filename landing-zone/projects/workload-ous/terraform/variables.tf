variable "region" {
  type        = string
  description = "AWS region (must match the Control Tower home region)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "ous" {
  type = map(object({
    enroll_baseline  = optional(bool, true)
    baseline_version = optional(string, "5.0")
  }))
  description = <<-EOT
    Flat map of OUs to create, keyed by full path. The parent is derived from
    the path: "Workloads/Prod" is a child of "Workloads". A single-segment path
    (e.g. "Workloads") is placed under the org root.

    Example:
      ous = {
        "Workloads"      = {}
        "Workloads/Prod" = {}
        "Workloads/Test" = { enroll_baseline = false, baseline_version = "5.0" }
      }
  EOT
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
