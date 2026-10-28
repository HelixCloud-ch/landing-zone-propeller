variable "name" {
  type        = string
  description = "Name of the Organizations backup policy. Also the plan name unless plan_name is set."
}

variable "description" {
  type        = string
  description = "Description of the Organizations backup policy."
  default     = "AWS Backup policy managed by propeller."
}

variable "target_ids" {
  type        = list(string)
  description = "Root, OU or account IDs the policy is attached to."

  validation {
    condition     = length(var.target_ids) > 0
    error_message = "target_ids must contain at least one root, OU or account ID."
  }

  validation {
    condition     = alltrue([for id in var.target_ids : can(regex("^(r-[0-9a-z]{4,32}|ou-[0-9a-z]{4,32}-[a-z0-9]{8,32}|\\d{12})$", id))])
    error_message = "target_ids entries must be root (r-...), OU (ou-...-...) or 12-digit account IDs."
  }
}

variable "plan_name" {
  type        = string
  description = "Backup plan name inside the policy. Defaults to name."
  default     = null
}

variable "rule_name" {
  type        = string
  description = "Name of the backup rule and of its tag selection."
  default     = "default"
}

variable "regions" {
  type        = list(string)
  description = "Regions the backup plan applies to."

  validation {
    condition     = length(var.regions) > 0 && alltrue([for r in var.regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", r))])
    error_message = "regions must be a non-empty list of AWS region codes (e.g. eu-central-2)."
  }
}

variable "schedule_expression" {
  type        = string
  description = "Schedule of the backup rule, e.g. cron(0 2 ? * * *)."

  validation {
    condition     = can(regex("^(cron|rate)\\(.+\\)$", var.schedule_expression))
    error_message = "schedule_expression must be a cron(...) or rate(...) expression."
  }
}

variable "start_window_minutes" {
  type        = number
  description = "Minutes after the schedule within which the job must start. Null keeps the AWS default."
  default     = null
}

variable "completion_window_minutes" {
  type        = number
  description = "Minutes within which the job must complete. Null keeps the AWS default."
  default     = null
}

variable "source_vault_name" {
  type        = string
  description = "Name of the vault receiving recovery points in each member account. Must exist in every target."
}

variable "source_retention_days" {
  type        = number
  description = "Source-vault retention. Kept short when a copy action holds the real retention."
  default     = 1

  validation {
    condition     = var.source_retention_days >= 1
    error_message = "source_retention_days must be at least 1."
  }
}

variable "iam_role_name" {
  type        = string
  description = "Name of the AWS Backup role that must exist in every member account the policy reaches."
}

variable "copy_vault_arn" {
  type        = string
  description = "Vault ARN (usually central) every recovery point is copied to. Null disables the copy."
  default     = null

  validation {
    condition     = var.copy_vault_arn == null || can(regex("^arn:aws[a-zA-Z-]*:backup:[a-z0-9-]+:\\d{12}:backup-vault:.+$", var.copy_vault_arn))
    error_message = "copy_vault_arn must be a backup vault ARN."
  }
}

variable "copy_retention_days" {
  type        = number
  description = "Retention of the copied recovery points. Required when copy_vault_arn is set."
  default     = null

  validation {
    condition     = (var.copy_vault_arn == null) == (var.copy_retention_days == null)
    error_message = "copy_retention_days must be set if and only if copy_vault_arn is set."
  }

  validation {
    condition     = var.copy_retention_days == null ? true : var.copy_retention_days >= 1
    error_message = "copy_retention_days must be at least 1."
  }
}

variable "selection_tag_key" {
  type        = string
  description = "Tag key that selects resources for backup."
  default     = "backup"
}

variable "selection_tag_values" {
  type        = list(string)
  description = "Tag values (any of) that select resources for backup."
  default     = ["default"]
}
