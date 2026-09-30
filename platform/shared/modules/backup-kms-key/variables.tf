variable "description" {
  type        = string
  description = "Description of the customer managed key."
}

variable "alias" {
  type        = string
  description = "Alias name for the key, without the 'alias/' prefix."
}

variable "cross_account_access" {
  type = object({
    account_ids     = optional(list(string), [])
    organization_id = optional(string)
    org_paths       = optional(list(string), [])
  })
  description = <<-EOT
    Principals outside this account allowed to use the key: explicit account IDs,
    and/or every principal in organization_id, optionally narrowed to org_paths.
    See README for the generated statements.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for id in var.cross_account_access.account_ids : can(regex("^\\d{12}$", id))])
    error_message = "cross_account_access.account_ids must contain 12-digit AWS account IDs."
  }

  validation {
    condition     = var.cross_account_access.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.cross_account_access.organization_id))
    error_message = "cross_account_access.organization_id must be a valid Organizations ID (o-xxxxxxxxxx)."
  }

  validation {
    condition     = length(var.cross_account_access.org_paths) == 0 || var.cross_account_access.organization_id != null
    error_message = "cross_account_access.org_paths requires cross_account_access.organization_id."
  }
}

variable "deletion_window_in_days" {
  type        = number
  description = "Waiting period before the key is deleted after a destroy (7-30)."
  default     = 30
}

variable "enable_rotation" {
  type        = bool
  description = "Enable automatic yearly key rotation."
  default     = true
}
