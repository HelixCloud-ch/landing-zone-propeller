variable "name" {
  type        = string
  description = "Name of the backup vault."

  validation {
    condition     = can(regex("^[a-zA-Z0-9\\-_]{2,50}$", var.name))
    error_message = "name must be 2-50 characters of letters, digits, hyphens or underscores."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of an existing customer managed key. Null (default) creates a dedicated key for the vault."
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:\\d{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "kms_key_alias" {
  type        = string
  description = "Alias (no 'alias/' prefix) for the created key. Defaults to backup/<name>; ignored with kms_key_arn."
  default     = null
}

variable "cross_account_access" {
  type = object({
    account_ids     = optional(list(string), [])
    organization_id = optional(string)
    org_paths       = optional(list(string), [])
  })
  description = <<-EOT
    Principals allowed to copy into this vault, and to use the created key:
    account IDs and/or an organization, optionally narrowed to org_paths.
    Empty (default) creates no vault access policy.
  EOT
  default     = {}
}

variable "vault_lock" {
  type = object({
    min_retention_days = number
    max_retention_days = number
  })
  description = "Governance-mode Vault Lock retention window. Null (default) leaves the vault unlocked."
  default     = null

  validation {
    condition     = var.vault_lock == null ? true : (var.vault_lock.min_retention_days >= 1 && var.vault_lock.max_retention_days >= var.vault_lock.min_retention_days)
    error_message = "vault_lock requires min_retention_days >= 1 and max_retention_days >= min_retention_days."
  }
}

variable "role_name" {
  type        = string
  description = "Name of the IAM role AWS Backup assumes for backup, copy and restore jobs in this account."
}

variable "enable_restores" {
  type        = bool
  description = "Also attach AWSBackupServiceRolePolicyForRestores to the role."
  default     = true
}
