variable "region" {
  type        = string
  description = "AWS region for the management account provider. Also the plan region of policies without regions."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Pipeline inputs ──────────────────────────────────────────────────────────

variable "ou_ids" {
  type        = map(string)
  description = "Map of OU path to OU ID, from @landing-zone/workload-parameters.ou_ids. Resolves target_ou_paths."
  default     = {}
}

variable "copy_vault_arn" {
  type        = string
  description = "Default destination vault ARN (e.g. the central backup-vault's vault_arn). Null disables copies."
  default     = null
}

# ── Policies ─────────────────────────────────────────────────────────────────

variable "policies" {
  type = map(object({
    description               = optional(string, "AWS Backup policy managed by propeller.")
    target_ou_paths           = optional(list(string), [])
    target_ids                = optional(list(string), [])
    regions                   = optional(list(string), [])
    schedule_expression       = optional(string, "cron(0 2 ? * * *)")
    start_window_minutes      = optional(number)
    completion_window_minutes = optional(number)
    source_vault_name         = optional(string, "propeller-backup")
    source_retention_days     = optional(number, 1)
    iam_role_name             = optional(string, "propeller-backup-role")
    copy_to_vault             = optional(bool, true)
    copy_vault_arn            = optional(string)
    copy_retention_days       = optional(number, 30)
    selection_tag_key         = optional(string, "backup")
    selection_tag_values      = optional(list(string), ["default"])
  }))
  description = <<-EOT
    Organizations backup policies to create, keyed by policy name (also the plan
    name). Every field is optional except the targets; see README for the field
    reference and the defaults' contract with backup-vault.
  EOT

  validation {
    condition     = length(var.policies) > 0
    error_message = "Define at least one policy."
  }

  validation {
    condition     = alltrue([for k, p in var.policies : length(p.target_ou_paths) + length(p.target_ids) > 0])
    error_message = "Every policy must set at least one of target_ou_paths or target_ids."
  }

  validation {
    condition     = alltrue(flatten([for k, p in var.policies : [for path in p.target_ou_paths : contains(keys(var.ou_ids), path)]]))
    error_message = "Every target_ou_paths entry must be a key of ou_ids."
  }

  validation {
    condition     = alltrue([for k, p in var.policies : !p.copy_to_vault || coalesce(p.copy_vault_arn, var.copy_vault_arn, "none") != "none"])
    error_message = "A policy with copy_to_vault = true needs copy_vault_arn (per policy or project-level)."
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
