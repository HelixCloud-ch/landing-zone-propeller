variable "region" {
  type        = string
  description = "AWS region where Control Tower will be deployed."
}

variable "log_archive_account_email" {
  type        = string
  description = "Root email address for the Log Archive account. Leave empty to skip creation."
  sensitive   = true
  default     = ""
}

variable "audit_account_email" {
  type        = string
  description = "Root email address for the Security Tooling (Audit) account. Leave empty to skip creation."
  sensitive   = true
  default     = ""
}

variable "log_archive_account_name" {
  type        = string
  description = "Friendly name for the Log Archive account."
  default     = "Log Archive"
}

variable "audit_account_name" {
  type        = string
  description = "Friendly name for the Security Tooling (Audit) account."
  default     = "Security Tooling"
}

variable "security_ou_name" {
  type        = string
  description = "Name of the Security OU that will contain Log Archive and Audit accounts."
  default     = "Security"
}

variable "backup_admin_account_email" {
  type        = string
  description = "Root email address for the Backup Administrator account. Leave empty to skip creation."
  sensitive   = true
  default     = ""
}

variable "backup_central_account_email" {
  type        = string
  description = "Root email address for the Central Backup account. Leave empty to skip creation."
  sensitive   = true
  default     = ""
}

variable "backup_admin_account_name" {
  type        = string
  description = "Friendly name for the Backup Administrator account."
  default     = "Backup Admin"
}

variable "backup_central_account_name" {
  type        = string
  description = "Friendly name for the Central Backup account."
  default     = "Central Backup"
}

variable "create_iam_roles" {
  type        = bool
  description = "Whether to create the four CT IAM service roles. Set to false if the roles already exist (e.g. a previous CT installation)."
  default     = true
}
