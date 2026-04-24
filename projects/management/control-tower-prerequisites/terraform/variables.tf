variable "region" {
  type        = string
  description = "AWS region where Control Tower will be deployed."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

# ── Core accounts ────────────────────────────────────────────────────────────

variable "log_archive_account_email" {
  type        = string
  description = "Root email address for the Log Archive account. Leave empty to skip creation."
  sensitive   = true
  default     = ""

  validation {
    condition     = var.log_archive_account_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.log_archive_account_email))
    error_message = "log_archive_account_email must be a valid email address or empty."
  }
}

variable "log_archive_account_name" {
  type        = string
  description = "Friendly name for the Log Archive account."
  default     = "Log Archive"

  validation {
    condition     = var.log_archive_account_name == "Log Archive" || var.log_archive_account_email != ""
    error_message = "log_archive_account_name is customized but log_archive_account_email is empty — provide the email to create the account."
  }
}

variable "audit_account_email" {
  type        = string
  description = "Root email address for the Security Tooling (Audit) account. Leave empty to skip creation."
  sensitive   = true
  default     = ""

  validation {
    condition     = var.audit_account_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.audit_account_email))
    error_message = "audit_account_email must be a valid email address or empty."
  }
}

variable "audit_account_name" {
  type        = string
  description = "Friendly name for the Security Tooling (Audit) account."
  default     = "Security Tooling"

  validation {
    condition     = var.audit_account_name == "Security Tooling" || var.audit_account_email != ""
    error_message = "audit_account_name is customized but audit_account_email is empty — provide the email to create the account."
  }
}

# ── Security OU ──────────────────────────────────────────────────────────────

variable "security_ou_name" {
  type        = string
  description = "Name of the Security OU that will contain the service integration accounts."
  default     = "Security"
}

# ── Backup accounts (optional) ───────────────────────────────────────────────

variable "backup_admin_account_email" {
  type        = string
  description = "Root email address for the Backup Administrator account. Leave empty to skip creation."
  sensitive   = true
  default     = ""

  validation {
    condition     = var.backup_admin_account_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.backup_admin_account_email))
    error_message = "backup_admin_account_email must be a valid email address or empty."
  }
}

variable "backup_admin_account_name" {
  type        = string
  description = "Friendly name for the Backup Administrator account."
  default     = "Backup Admin"

  validation {
    condition     = var.backup_admin_account_name == "Backup Admin" || var.backup_admin_account_email != ""
    error_message = "backup_admin_account_name is customized but backup_admin_account_email is empty — provide the email to create the account."
  }
}

variable "backup_central_account_email" {
  type        = string
  description = "Root email address for the Central Backup account. Leave empty to skip creation."
  sensitive   = true
  default     = ""

  validation {
    condition     = var.backup_central_account_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.backup_central_account_email))
    error_message = "backup_central_account_email must be a valid email address or empty."
  }

  validation {
    condition     = (var.backup_central_account_email == "") == (var.backup_admin_account_email == "")
    error_message = "Backup accounts must be created together — provide both backup_admin_account_email and backup_central_account_email, or neither."
  }
}

variable "backup_central_account_name" {
  type        = string
  description = "Friendly name for the Central Backup account."
  default     = "Central Backup"

  validation {
    condition     = var.backup_central_account_name == "Central Backup" || var.backup_central_account_email != ""
    error_message = "backup_central_account_name is customized but backup_central_account_email is empty — provide the email to create the account."
  }
}

# ── IAM roles ────────────────────────────────────────────────────────────────

variable "create_iam_roles" {
  type        = bool
  description = "Whether to create the four CT IAM service roles. Set to false if the roles already exist (e.g. a previous CT installation)."
  default     = true
}
