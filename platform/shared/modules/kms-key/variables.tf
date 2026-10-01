variable "description" {
  type        = string
  description = "Description of the customer managed key."
}

variable "alias" {
  type        = string
  description = "Alias name for the key, without the 'alias/' prefix."

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]{1,250}$", var.alias)) && !startswith(var.alias, "aws/")
    error_message = "alias must be 1-250 characters of [a-zA-Z0-9/_-], without the 'alias/' prefix, and must not start with 'aws/'."
  }
}

variable "policy_json" {
  type        = string
  description = "Key policy document (JSON), e.g. the json output of backup-kms-key-policy."
}

variable "enable_rotation" {
  type        = bool
  description = "Enable automatic key rotation. Not supported for imported or custom key store key material."
  default     = true
}

variable "rotation_period_in_days" {
  type        = number
  description = "Rotation period (90-2560 days). Null keeps the AWS default of 365; ignored without rotation."
  default     = null

  validation {
    condition     = var.rotation_period_in_days == null || (var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560)
    error_message = "rotation_period_in_days must be between 90 and 2560."
  }
}

variable "deletion_window_in_days" {
  type        = number
  description = "Waiting period before the key is deleted after a destroy (7-30)."
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}
