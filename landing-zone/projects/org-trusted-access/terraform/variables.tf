variable "enable_ram_org_sharing" {
  type        = bool
  description = "Enable RAM sharing with AWS Organizations. Required before any RAM share can target OU ARNs without per-account invitations."
  default     = true
}

variable "region" {
  type        = string
  description = "AWS region for the management account provider."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region code (e.g. eu-central-2)."
  }
}

variable "trusted_service_principals" {
  type        = list(string)
  description = <<-EOT
    Service principals to enable for trusted access with AWS Organizations.
    Each entry maps to one aws_organizations_aws_service_access resource.

    Example:
      trusted_service_principals = ["securityhub.amazonaws.com"]

    Full list of supported principals:
    https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_list.html
  EOT
  default     = []
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
